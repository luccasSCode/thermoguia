import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../app_deps.dart';
import '../http/http_utils.dart';

/// Ações sensíveis: tudo passa por aprovação explícita e fica no log.
void registerSafetyRoutes(Router r, AppDeps d) {
  r.get('/emergency/contacts', (Request req) async =>
      jsonResponse(await d.contacts.list(userIdOf(req))));

  r.post('/emergency/contacts', (Request req) async {
    final b = await readJson(req);
    final phone = bodyString(b, 'phone', max: 30).replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.length < 10) throw ApiError(400, 'Informe o telefone com DDD.');
    final c = await d.contacts.add(
      userIdOf(req),
      bodyString(b, 'name', max: 80),
      phone,
      (b['relation'] as String? ?? '').trim(),
    );
    await d.audit.log(userIdOf(req), 'contato_emergencia_adicionado',
        approved: true, details: {'contactId': c['id']}, source: 'servidor');
    return jsonResponse(c, status: 201);
  });

  r.delete('/emergency/contacts/<id>', (Request req, String id) async {
    await d.contacts.remove(userIdOf(req), id);
    await d.audit.log(userIdOf(req), 'contato_emergencia_removido',
        approved: true, details: {'contactId': id}, source: 'servidor');
    return jsonResponse({'ok': true});
  });

  /// Registra a decisão do usuário sobre uma ação de emergência.
  /// Se aprovada, devolve a mensagem pronta; o envio acontece no aparelho,
  /// pelo próprio usuário (WhatsApp/SMS), mantendo-o no controle.
  r.post('/emergency/events', (Request req) async {
    final b = await readJson(req);
    final action = bodyString(b, 'action', max: 40);
    if (!{'share_location', 'call_samu', 'dismiss'}.contains(action)) {
      throw ApiError(400, 'Ação de emergência inválida.');
    }
    final approved = b['approved'] == true;
    final lat = (b['lat'] as num?)?.toDouble();
    final lng = (b['lng'] as num?)?.toDouble();

    await d.audit.log(userIdOf(req), 'emergencia_$action', approved: approved, details: {
      'symptoms': b['symptoms'] ?? const [],
      'contactIds': b['contactIds'] ?? const [],
      'riskLevel': b['riskLevel'],
      if (approved && lat != null) 'lat': lat,
      if (approved && lng != null) 'lng': lng,
      'trigger': b['trigger'] ?? 'usuario',
    });

    if (!approved || action != 'share_location' || lat == null || lng == null) {
      return jsonResponse({'logged': true});
    }
    // Localização compartilhada com aprovação: o responsável vê no link de acompanhamento.
    // Completa o pedido de ajuda aberto há pouco, em vez de criar outro.
    final params = {'u': userIdOf(req), 's': jsonEncode(b['symptoms'] ?? const []), 'lat': lat, 'lng': lng};
    final updated = await d.db.query(
      '''UPDATE help_alerts SET lat = @lat, lng = @lng, symptoms = CAST(@s AS jsonb)
         WHERE id = (SELECT id FROM help_alerts WHERE user_id = CAST(@u AS uuid)
                     AND created_at > now() - interval '15 minutes' ORDER BY created_at DESC LIMIT 1)
         RETURNING id''',
      params,
    );
    if (updated.isEmpty) {
      await d.db.query(
        'INSERT INTO help_alerts (user_id, symptoms, lat, lng) VALUES (CAST(@u AS uuid), CAST(@s AS jsonb), @lat, @lng)',
        params,
      );
    }
    final user = await d.users.byId(userIdOf(req));
    final name = (user?['name'] as String?)?.isNotEmpty == true ? user!['name'] : 'Uma pessoa';
    final maps = 'https://maps.google.com/?q=${lat.toStringAsFixed(6)},${lng.toStringAsFixed(6)}';
    return jsonResponse({
      'logged': true,
      'mapsUrl': maps,
      'message': '$name pediu ajuda pelo ThermoGuia: pode estar passando mal por causa do calor. '
          'Localização: $maps',
    });
  });

  r.post('/audit', (Request req) async {
    final b = await readJson(req);
    final details = b['details'];
    final entry = await d.audit.log(
      userIdOf(req),
      bodyString(b, 'action', max: 80),
      approved: b['approved'] as bool?,
      details: details is Map ? details.cast<String, dynamic>() : const {},
    );
    return jsonResponse(entry, status: 201);
  });

  r.get('/audit', (Request req) async =>
      jsonResponse(await d.audit.list(userIdOf(req), limit: qInt(req, 'limit', 50).clamp(1, 200))));
}
