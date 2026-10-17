import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../app_deps.dart';
import '../cities.dart';
import '../http/http_utils.dart';
import '../services/assistant_rules.dart';
import '../services/assistant_service.dart';

void registerAssistantRoutes(Router r, AppDeps d) {
  final briefingCache = <String, (DateTime, Map<String, dynamic>)>{};

  Future<(AssistantContext, Map<String, dynamic>, City)> context(
    Request req,
    GeoPoint at,
    int exposure,
    int water,
  ) async {
    final user = await d.users.byId(userIdOf(req));
    if (user == null) throw ApiError(401, 'Sessão expirada. Entre novamente.');
    final city = cityById(user['city_id'] as String?);
    final ctx = await d.assistants[city.id]!.buildContext(
      city: city,
      at: at,
      userName: user['name'] as String? ?? '',
      persona: Persona.fromName(user['persona'] as String?),
      profile: await d.profiles.get(user['id'] as String),
      exposureMin: exposure,
      waterMl: water,
    );
    return (ctx, user, city);
  }

  r.post('/ai/chat', (Request req) async {
    final b = await readJson(req);
    final c = (b['context'] as Map?)?.cast<String, dynamic>() ?? const {};
    final at = GeoPoint(
      (c['lat'] as num?)?.toDouble() ?? manaus.center.lat,
      (c['lng'] as num?)?.toDouble() ?? manaus.center.lng,
    );

    // Normaliza o histórico: alterna papéis, começa pelo usuário, limita tamanho.
    final raw = (b['messages'] as List? ?? const []).cast<Map>();
    final messages = <Map<String, String>>[];
    for (final m in raw.skip(raw.length > 12 ? raw.length - 12 : 0)) {
      final role = m['role'] == 'assistant' ? 'assistant' : 'user';
      var text = '${m['content'] ?? ''}'.trim();
      if (text.isEmpty) continue;
      if (text.length > 2000) text = text.substring(0, 2000);
      if (messages.isNotEmpty && messages.last['role'] == role) {
        messages.last['content'] = '${messages.last['content']}\n$text';
      } else {
        messages.add({'role': role, 'content': text});
      }
    }
    while (messages.isNotEmpty && messages.first['role'] != 'user') {
      messages.removeAt(0);
    }
    if (messages.isEmpty || messages.last['role'] != 'user') {
      throw ApiError(400, 'Envie uma pergunta.');
    }

    final (ctx, user, city) = await context(
      req,
      at,
      (c['exposureMinutes'] as num?)?.toInt() ?? 0,
      (c['waterMlToday'] as num?)?.toInt() ?? 0,
    );
    // Recusas de assuntos internos não gastam perguntas do dia.
    if (TopicGuard.isInternal(messages.last['content']!)) {
      return jsonResponse({'reply': TopicGuard.reply, 'source': 'regras', 'risk': ctx.risk.toJson()});
    }
    final limit = user['plan'] == 'plus' ? d.config.plusAiDailyLimit : d.config.freeAiDailyLimit;
    final used = await d.aiUsage.increment(user['id'] as String, city.localWallClock(DateTime.now()));
    if (used > limit) {
      throw ApiError(429, 'Você usou as $limit perguntas de hoje. '
          'No ThermoGuia+ o assistente não tem esse limite.');
    }

    final (reply, source) = await d.assistants[city.id]!.reply(ctx, messages);
    return jsonResponse({
      'reply': reply,
      'source': source,
      'remainingToday': limit - used,
      'risk': ctx.risk.toJson(),
    });
  });

  r.get('/ai/briefing', (Request req) async {
    final at = GeoPoint(qDouble(req, 'lat'), qDouble(req, 'lng'));
    final key = '${userIdOf(req)}:${(at.lat * 50).round()}:${(at.lng * 50).round()}';
    final hit = briefingCache[key];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 90) {
      return jsonResponse(hit.$2);
    }
    final (ctx, _, city) = await context(
      req,
      at,
      qInt(req, 'exposureMinutes', 0),
      qInt(req, 'waterMl', 0),
    );
    final (text, source) = await d.assistants[city.id]!.briefing(ctx);
    final body = {'text': text, 'source': source, 'generatedAt': DateTime.now()};
    briefingCache[key] = (DateTime.now(), body);
    return jsonResponse(body);
  });
}
