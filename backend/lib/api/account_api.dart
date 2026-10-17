import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../app_deps.dart';
import '../cities.dart';
import '../data/repositories.dart';
import '../http/http_utils.dart';
import 'rewards_api.dart';

final _emailRe = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

void registerAccountRoutes(Router r, AppDeps d) {
  Future<Map<String, dynamic>> session(Map<String, dynamic> user) async =>
      {'token': d.auth.issueToken(user['id'] as String), 'user': userJson(user)};

  String persona(Map<String, dynamic> b) => Persona.fromName(b['persona'] as String?).name;

  void validateCredentials(String email, String password) {
    if (!_emailRe.hasMatch(email)) throw ApiError(400, 'Informe um e-mail válido.');
    if (password.length < 8) throw ApiError(400, 'A senha precisa ter pelo menos 8 caracteres.');
  }

  r.post('/auth/register', (Request req) async {
    final b = await readJson(req);
    final email = bodyString(b, 'email', max: 200).toLowerCase();
    final password = bodyString(b, 'password', max: 200);
    validateCredentials(email, password);
    if (await d.users.byEmail(email) != null) {
      throw ApiError(409, 'Este e-mail já tem conta. Use "Entrar".');
    }
    final user = await d.users.create(
      email: email,
      passwordHash: d.auth.hashPassword(password),
      name: (b['name'] as String? ?? '').trim(),
      persona: persona(b),
      anonymous: false,
    );
    await d.audit.log(user['id'] as String, 'conta_criada', source: 'servidor');
    return jsonResponse(await session(user), status: 201);
  });

  r.post('/auth/login', (Request req) async {
    final b = await readJson(req);
    final user = await d.users.byEmail(bodyString(b, 'email', max: 200));
    final hash = user?['password_hash'] as String?;
    if (user == null || hash == null || !d.auth.checkPassword(bodyString(b, 'password'), hash)) {
      throw ApiError(401, 'E-mail ou senha incorretos.');
    }
    return jsonResponse(await session(user));
  });

  /// Conta sem e-mail: o usuário começa a usar na hora e pode
  /// adicionar e-mail depois sem perder dados.
  r.post('/auth/anonymous', (Request req) async {
    final b = await readJson(req);
    final user = await d.users.create(
      name: (b['name'] as String? ?? '').trim(),
      persona: persona(b),
      anonymous: true,
    );
    return jsonResponse(await session(user), status: 201);
  });

  r.get('/me', (Request req) async {
    final user = await d.users.byId(userIdOf(req));
    if (user == null) throw ApiError(401, 'Sessão expirada. Entre novamente.');
    return jsonResponse(userJson(user));
  });

  r.patch('/me', (Request req) async {
    final b = await readJson(req);
    final user = await d.users.update(
      userIdOf(req),
      name: (b['name'] as String?)?.trim(),
      persona: b['persona'] == null ? null : persona(b),
    );
    return jsonResponse(userJson(user));
  });

  // Foto de perfil: corpo é a própria imagem (image/jpeg ou image/png), até 512 KB.
  // O app já envia reduzida (512 px, ~50 KB).
  const maxAvatarBytes = 512 * 1024;
  r.put('/me/avatar', (Request req) async {
    // Lê o corpo até o fim antes de responder (responder no meio derruba a
    // conexão), mas só guarda até o limite e desiste acima de 10 MB.
    final bytes = <int>[];
    var total = 0;
    await for (final chunk in req.read()) {
      total += chunk.length;
      if (total > 10 * 1024 * 1024) break;
      if (total <= maxAvatarBytes) bytes.addAll(chunk);
    }
    if (total > maxAvatarBytes) throw ApiError(413, 'A foto é grande demais. Tente outra imagem.');
    final mime = _imageMime(bytes);
    if (mime == null) throw ApiError(400, 'Envie uma foto em JPEG ou PNG.');
    return jsonResponse(userJson(await d.users.setAvatar(userIdOf(req), bytes, mime)));
  });

  r.get('/me/avatar', (Request req) async {
    final a = await d.users.avatar(userIdOf(req));
    if (a == null) throw ApiError(404, 'Sem foto de perfil.');
    return Response.ok(a['image'] as List<int>, headers: {
      'content-type': a['mime'] as String,
      'cache-control': 'private, max-age=86400',
    });
  });

  r.delete('/me/avatar', (Request req) async => jsonResponse(userJson(await d.users.removeAvatar(userIdOf(req)))));

  r.post('/me/credentials', (Request req) async {
    final b = await readJson(req);
    final email = bodyString(b, 'email', max: 200).toLowerCase();
    final password = bodyString(b, 'password', max: 200);
    validateCredentials(email, password);
    final existing = await d.users.byEmail(email);
    if (existing != null && existing['id'] != userIdOf(req)) {
      throw ApiError(409, 'Este e-mail já está em uso.');
    }
    final user = await d.users.setCredentials(userIdOf(req), email, d.auth.hashPassword(password));
    return jsonResponse(userJson(user));
  });

  /// Exclusão de conta (LGPD). Os registros de auditoria são anonimizados.
  r.delete('/me', (Request req) async {
    final id = userIdOf(req);
    await d.audit.log(id, 'conta_excluida', approved: true, source: 'servidor');
    await d.users.delete(id);
    return jsonResponse({'deleted': true});
  });

  r.get('/profile/adaptive', (Request req) async =>
      jsonResponse((await d.profiles.get(userIdOf(req))).toJson()));

  r.put('/profile/adaptive', (Request req) async {
    final p = AdaptiveProfile.fromJson(await readJson(req));
    await d.profiles.save(userIdOf(req), p);
    return jsonResponse(p.toJson());
  });

  r.post('/hydration', (Request req) async {
    final b = await readJson(req);
    final ml = (b['amountMl'] as num?)?.toInt() ?? 0;
    if (ml <= 0 || ml > 2000) throw ApiError(400, 'Quantidade de água inválida.');
    final at = DateTime.tryParse('${b['loggedAt']}') ?? DateTime.now();
    await d.hydration.add(userIdOf(req), ml, at);

    // O registro tocando na tela serve para o seu controle e os lembretes.
    // Gotas do Clube H2O só com a água comprovada por foto (Comunidade).
    return jsonResponse({'ok': true}, status: 201);
  });

  r.get('/hydration/today', (Request req) async {
    final user = await d.users.byId(userIdOf(req));
    final city = cityById(user?['city_id'] as String?);
    final local = city.localWallClock(DateTime.now());
    final startLocal = DateTime.utc(local.year, local.month, local.day);
    final startUtc = startLocal.subtract(city.utcOffset);
    final logs = await d.hydration.since(userIdOf(req), startUtc);
    final total = logs.fold<int>(0, (a, l) => a + (l['amount_ml'] as int));
    return jsonResponse({
      'totalMl': total,
      'logs': logs.map((l) => {'amountMl': l['amount_ml'], 'loggedAt': l['logged_at']}).toList(),
    });
  });

  r.post('/trips', (Request req) async {
    final b = await readJson(req);
    final trip = await d.trips.create(userIdOf(req), b);

    // Clube H2O: só conta trajeto de verdade (2 min e 200 m ou mais).
    final dur = (b['durationS'] as num?)?.toDouble() ?? 0;
    final dist = (b['distanceM'] as num?)?.toDouble() ?? 0;
    Map<String, dynamic>? reward;
    if (dur >= 120 && dist >= 200) {
      final (city, plus) = await rewardsContext(d, req);
      final shady = ((b['shadeScore'] as num?)?.toDouble() ?? 0) >= 0.5;
      reward = await d.rewards.award(userIdOf(req), 'trajeto', city, plus: plus, bonus: shady ? 5 : 0, ref: '${trip['id']}');
    }
    return jsonResponse({...trip, if (reward != null) 'reward': reward}, status: 201);
  });

  r.get('/trips', (Request req) async =>
      jsonResponse(await d.trips.recent(userIdOf(req), limit: qInt(req, 'limit', 30).clamp(1, 100))));
}

/// Confere a assinatura do arquivo, não a extensão nem o cabeçalho enviado.
String? _imageMime(List<int> b) {
  if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) return 'image/jpeg';
  if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return 'image/png';
  return null;
}
