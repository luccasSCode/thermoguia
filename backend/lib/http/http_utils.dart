import 'dart:convert';

import 'package:shelf/shelf.dart';

/// Erro com mensagem pronta para o usuário.
class ApiError implements Exception {
  ApiError(this.status, this.message);
  final int status;
  final String message;

  @override
  String toString() => 'ApiError($status): $message';
}

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response jsonResponse(Object? body, {int status = 200}) =>
    Response(status, body: jsonEncode(_safe(body)), headers: _jsonHeaders);

Object? _safe(Object? v) {
  if (v is DateTime) return v.toUtc().toIso8601String();
  if (v is Map) return v.map((k, val) => MapEntry('$k', _safe(val)));
  if (v is Iterable) return v.map(_safe).toList();
  return v;
}

Future<Map<String, dynamic>> readJson(Request r) async {
  final raw = await r.readAsString();
  if (raw.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
  } catch (_) {}
  throw ApiError(400, 'Corpo da requisição inválido.');
}

String userIdOf(Request r) => r.context['userId']! as String;

double qDouble(Request r, String key) {
  final v = double.tryParse(r.url.queryParameters[key] ?? '');
  if (v == null) throw ApiError(400, 'Parâmetro "$key" ausente ou inválido.');
  return v;
}

int qInt(Request r, String key, int fallback) =>
    int.tryParse(r.url.queryParameters[key] ?? '') ?? fallback;

double bodyDouble(Map<String, dynamic> b, String key) {
  final v = b[key];
  if (v is num) return v.toDouble();
  throw ApiError(400, 'Campo "$key" ausente ou inválido.');
}

String bodyString(Map<String, dynamic> b, String key, {int max = 500}) {
  final v = b[key];
  if (v is! String || v.trim().isEmpty) {
    throw ApiError(400, 'Campo "$key" é obrigatório.');
  }
  final s = v.trim();
  return s.length > max ? s.substring(0, max) : s;
}
