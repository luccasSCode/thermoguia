import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Cliente mínimo da API de Mensagens do Claude (Anthropic).
/// A chave fica apenas no servidor; o app nunca a recebe.
class ClaudeService {
  ClaudeService(this._config, this._client);
  final Config _config;
  final http.Client _client;

  bool get enabled => _config.anthropicApiKey.isNotEmpty;

  /// Retorna o texto da resposta, ou `null` se a IA estiver indisponível
  /// (quem chama deve então usar o motor de regras).
  Future<String?> complete({
    required String system,
    required List<Map<String, String>> messages,
    int maxTokens = 600,
  }) async {
    if (!enabled) return null;
    try {
      final res = await _client
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': _config.anthropicApiKey,
              'anthropic-version': '2023-06-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _config.anthropicModel,
              'max_tokens': maxTokens,
              'system': system,
              'messages': messages,
            }),
          )
          .timeout(const Duration(seconds: 40));
      if (res.statusCode != 200) {
        stderr.writeln('[claude] HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final text = (data['content'] as List)
          .cast<Map<String, dynamic>>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String)
          .join('\n')
          .trim();
      return text.isEmpty ? null : text;
    } catch (e) {
      stderr.writeln('[claude] $e');
      return null;
    }
  }

  /// Analisa imagens e devolve um JSON no formato de [schema] (structured
  /// outputs). Devolve `null` quando não há resposta confiável (sem chave,
  /// erro, recusa ou corte): quem chama manda o caso para revisão humana,
  /// nunca aprova por falta de resposta.
  Future<Map<String, dynamic>?> analyzeImages({
    required String system,
    required List<(List<int>, String)> images,
    required String instruction,
    required Map<String, dynamic> schema,
  }) async {
    if (!enabled) return null;
    try {
      final res = await _client
          .post(
            Uri.parse('https://api.anthropic.com/v1/messages'),
            headers: {
              'x-api-key': _config.anthropicApiKey,
              'anthropic-version': '2023-06-01',
              // Se o modelo principal recusar, o servidor tenta outro modelo.
              'anthropic-beta': 'server-side-fallback-2026-07-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': _config.anthropicVisionModel,
              'max_tokens': 8000,
              'thinking': {'type': 'adaptive'},
              'output_config': {
                'effort': 'high',
                'format': {'type': 'json_schema', 'schema': schema},
              },
              'fallbacks': 'default',
              'system': system,
              'messages': [
                {
                  'role': 'user',
                  'content': [
                    for (final (bytes, mime) in images)
                      {
                        'type': 'image',
                        'source': {'type': 'base64', 'media_type': mime, 'data': base64Encode(bytes)},
                      },
                    {'type': 'text', 'text': instruction},
                  ],
                }
              ],
            }),
          )
          .timeout(const Duration(seconds: 90));
      if (res.statusCode != 200) {
        stderr.writeln('[claude-visao] HTTP ${res.statusCode}: ${res.body}');
        return null;
      }
      final data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      final stop = data['stop_reason'];
      if (stop != 'end_turn') {
        stderr.writeln('[claude-visao] sem resposta utilizável (stop_reason: $stop)');
        return null;
      }
      final text = (data['content'] as List)
          .cast<Map<String, dynamic>>()
          .where((b) => b['type'] == 'text')
          .map((b) => b['text'] as String)
          .join();
      return jsonDecode(text) as Map<String, dynamic>;
    } catch (e) {
      stderr.writeln('[claude-visao] $e');
      return null;
    }
  }
}
