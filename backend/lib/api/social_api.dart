import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../app_deps.dart';
import '../cities.dart';
import '../http/http_utils.dart';
import '../services/verification_service.dart';
import 'admin_page.dart';

/// Corpo JSON com a foto em base64 (limite de 2,5 MB no corpo inteiro).
Future<(Map<String, dynamic>, List<int>?)> _readPhotoBody(Request req) async {
  final raw = <int>[];
  await for (final chunk in req.read()) {
    raw.addAll(chunk);
    if (raw.length > 2560 * 1024) throw ApiError(413, 'A foto é grande demais.');
  }
  final Map<String, dynamic> b;
  try {
    b = jsonDecode(utf8.decode(raw)) as Map<String, dynamic>;
  } catch (_) {
    throw ApiError(400, 'Corpo da requisição inválido.');
  }
  final img = b['image'];
  if (img == null) return (b, null);
  try {
    return (b, base64Decode(img as String));
  } catch (_) {
    throw ApiError(400, 'Foto inválida.');
  }
}

Map<String, dynamic> postJson(Map<String, dynamic> p, Map<String, List<String>> badges) {
  final author = '${p['author_name'] ?? ''}'.trim();
  return {
    'id': p['id'],
    'userId': p['user_id'],
    'author': author.isEmpty ? 'Alguém' : author.split(' ').first,
    'authorAvatar': p['author_avatar'],
    'authorBadges': badges[p['user_id']] ?? const [],
    'category': p['category'],
    'caption': p['caption'],
    'status': p['status'],
    'reason': p['reason'],
    'verifiedMl': p['verified_ml'],
    'verifiedBy': p['verified_by'],
    'createdAt': p['created_at'],
    'reactions': p['reactions'] ?? 0,
    'byKind': p['by_kind'] ?? const {},
    'comments': p['comments'] ?? 0,
    'myReaction': p['my_reaction'],
    'images': [if (p['has_before'] == true) ...['antes', 'depois'] else 'foto'],
  };
}

void registerSocialRoutes(Router r, AppDeps d) {
  Future<(City, Map<String, dynamic>)> who(Request req) async {
    final user = await d.users.byId(userIdOf(req));
    if (user == null) throw ApiError(401, 'Sessão expirada. Entre novamente.');
    return (cityById(user['city_id'] as String?), user);
  }

  r.get('/social/categories', (Request _) => jsonResponse([
        for (final c in postCategories) {'id': c.id, 'label': c.label, 'badge': c.badge, 'evidence': c.evidence},
      ]));

  r.get('/social/feed', (Request req) async {
    final (city, _) = await who(req);
    final before = DateTime.tryParse(req.url.queryParameters['before'] ?? '');
    final badges = await d.social.badgesByUser(city);
    final rows = await d.socialRepo.feed(userIdOf(req), before: before, limit: 20);
    return jsonResponse([for (final p in rows) postJson(p, badges)]);
  });

  r.get('/social/mine', (Request req) async {
    final (city, _) = await who(req);
    final badges = await d.social.badgesByUser(city);
    return jsonResponse([for (final p in await d.socialRepo.mine(userIdOf(req))) postJson(p, badges)]);
  });

  r.get('/social/badges', (Request req) async {
    final (city, _) = await who(req);
    return jsonResponse(await d.social.badges(city));
  });

  /// A foto só é servida se o post estiver público (aprovado e visível) ou
  /// for da própria pessoa.
  r.get('/social/posts/<id>/image/<kind>', (Request req, String id, String kind) async {
    final view = await d.socialRepo.postView(id, userIdOf(req));
    final mine = view != null && view['user_id'] == userIdOf(req);
    final public = view != null && view['status'] == 'aprovado';
    final p = await d.socialRepo.post(id);
    if (!mine && (!public || p?['hidden'] == true)) throw ApiError(404, 'Foto não encontrada.');
    final img = await d.socialRepo.image(id, kind);
    if (img == null) throw ApiError(404, 'Foto não encontrada.');
    return Response.ok(img['image'] as List<int>,
        headers: {'content-type': img['mime'] as String, 'cache-control': 'private, max-age=86400'});
  });

  r.post('/social/posts', (Request req) async {
    final (b, photo) = await _readPhotoBody(req);
    if (photo == null) throw ApiError(400, 'Envie a foto.');
    final (city, _) = await who(req);
    final p = await d.social.createPost(userIdOf(req), city, '${b['category']}', b['caption'] as String?, photo);
    return jsonResponse(postJson((await d.socialRepo.postView(p['id'] as String, userIdOf(req)))!, const {}), status: 201);
  });

  r.post('/social/water', (Request req) async {
    final (_, photo) = await _readPhotoBody(req);
    if (photo == null) throw ApiError(400, 'Envie a foto do recipiente.');
    final (city, _) = await who(req);
    final p = await d.social.startWater(userIdOf(req), city, photo);
    return jsonResponse(postJson((await d.socialRepo.postView(p['id'] as String, userIdOf(req)))!, const {}), status: 201);
  });

  r.post('/social/water/<id>/finish', (Request req, String id) async {
    final (b, photo) = await _readPhotoBody(req);
    if (photo == null) throw ApiError(400, 'Envie a foto de depois.');
    await d.social.finishWater(userIdOf(req), id, b['caption'] as String?, photo);
    return jsonResponse(postJson((await d.socialRepo.postView(id, userIdOf(req)))!, const {}));
  });

  r.get('/social/posts/<id>', (Request req, String id) async {
    final (city, _) = await who(req);
    final p = await d.socialRepo.postView(id, userIdOf(req));
    if (p == null || (p['user_id'] != userIdOf(req) && p['status'] != 'aprovado')) {
      throw ApiError(404, 'Publicação não encontrada.');
    }
    return jsonResponse(postJson(p, await d.social.badgesByUser(city)));
  });

  r.delete('/social/posts/<id>', (Request req, String id) async {
    if (await d.socialRepo.deletePost(id, userIdOf(req)) == 0) throw ApiError(404, 'Publicação não encontrada.');
    return jsonResponse({'ok': true});
  });

  Future<void> requirePublic(Request req, String id) async {
    final p = await d.socialRepo.postView(id, userIdOf(req));
    if (p == null || p['status'] != 'aprovado') throw ApiError(404, 'Publicação não encontrada.');
  }

  r.put('/social/posts/<id>/reaction', (Request req, String id) async {
    final kind = bodyString(await readJson(req), 'kind', max: 20);
    if (!const {'curtir', 'hidratado', 'protegido', 'inspirou'}.contains(kind)) {
      throw ApiError(400, 'Reação inválida.');
    }
    await requirePublic(req, id);
    await d.socialRepo.react(id, userIdOf(req), kind);
    return jsonResponse({'ok': true});
  });

  r.delete('/social/posts/<id>/reaction', (Request req, String id) async {
    await d.socialRepo.unreact(id, userIdOf(req));
    return jsonResponse({'ok': true});
  });

  r.get('/social/posts/<id>/comments', (Request req, String id) async {
    await requirePublic(req, id);
    final rows = await d.socialRepo.comments(id, userIdOf(req));
    return jsonResponse([
      for (final c in rows)
        {
          'id': c['id'],
          'userId': c['user_id'],
          'author': '${c['author_name'] ?? ''}'.trim().isEmpty ? 'Alguém' : '${c['author_name']}'.trim().split(' ').first,
          'authorAvatar': c['author_avatar'],
          'text': c['text'],
          'createdAt': c['created_at'],
        }
    ]);
  });

  r.post('/social/posts/<id>/comments', (Request req, String id) async {
    final text = bodyString(await readJson(req), 'text', max: 500).trim();
    if (text.isEmpty) throw ApiError(400, 'Escreva um comentário.');
    await requirePublic(req, id);
    return jsonResponse(await d.socialRepo.addComment(id, userIdOf(req), text), status: 201);
  });

  r.delete('/social/comments/<id>', (Request req, String id) async {
    if (await d.socialRepo.deleteComment(id, userIdOf(req)) == 0) throw ApiError(404, 'Comentário não encontrado.');
    return jsonResponse({'ok': true});
  });

  r.post('/social/report', (Request req) async {
    final b = await readJson(req);
    final type = bodyString(b, 'type', max: 20);
    if (type != 'post' && type != 'comentario') throw ApiError(400, 'Tipo inválido.');
    final reason = (b['reason'] as String? ?? '').trim();
    await d.socialRepo.report(type, bodyString(b, 'id', max: 64), userIdOf(req),
        reason.length > 280 ? reason.substring(0, 280) : reason);
    await d.audit.log(userIdOf(req), 'denuncia_conteudo', details: {'tipo': type});
    return jsonResponse({'ok': true});
  });

  r.post('/social/users/<id>/block', (Request req, String id) async {
    if (id == userIdOf(req)) throw ApiError(400, 'Você não pode bloquear a si mesmo.');
    await d.socialRepo.block(userIdOf(req), id);
    return jsonResponse({'ok': true});
  });

  /// Foto de perfil de quem aparece na Comunidade.
  r.get('/social/users/<id>/avatar', (Request req, String id) async {
    final a = await d.users.avatar(id);
    if (a == null) throw ApiError(404, 'Sem foto de perfil.');
    return Response.ok(a['image'] as List<int>,
        headers: {'content-type': a['mime'] as String, 'cache-control': 'private, max-age=86400'});
  });
}

/// Fila de revisão humana. Protegida por ADMIN_TOKEN (cabeçalho X-Admin-Token);
/// sem token configurado, as rotas não existem.
void registerAdminRoutes(Router r, AppDeps d) {
  void guard(Request req) {
    final token = d.config.adminToken;
    if (token.isEmpty || req.headers['x-admin-token'] != token) throw ApiError(404, 'Rota não encontrada.');
  }

  /// Página da fila (sem dados: pede a chave e usa as rotas abaixo).
  r.get('/admin/revisao', (Request _) => Response.ok(adminReviewPage, headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'no-store',
        'referrer-policy': 'no-referrer',
        'x-robots-tag': 'noindex',
      }));

  r.get('/admin/queue', (Request req) async {
    guard(req);
    return jsonResponse(await d.socialRepo.reviewQueue());
  });

  r.get('/admin/posts/<id>/image/<kind>', (Request req, String id, String kind) async {
    guard(req);
    final img = await d.socialRepo.image(id, kind);
    if (img == null) throw ApiError(404, 'Foto não encontrada.');
    return Response.ok(img['image'] as List<int>, headers: {'content-type': img['mime'] as String});
  });

  /// `{approve: true|false, ml?: int, reason?: string}`
  r.post('/admin/posts/<id>/decide', (Request req, String id) async {
    guard(req);
    final b = await readJson(req);
    final approve = b['approve'] == true;
    final p = await d.socialRepo.post(id);
    if (p == null) throw ApiError(404, 'Publicação não encontrada.');
    final ml = (b['ml'] as num?)?.toInt() ?? (p['verified_ml'] as int?);
    if (approve && p['category'] == 'agua' && (ml == null || ml < 100)) {
      throw ApiError(400, 'Informe os ml comprovados (100 ou mais).');
    }
    final reason = (b['reason'] as String?)?.trim();
    final decision = Decision(
      approve ? 'aprovado' : 'recusado',
      reason?.isNotEmpty == true
          ? reason!
          : (approve ? 'Aprovado pela equipe.' : 'A equipe não conseguiu confirmar pela foto.'),
      ml: approve ? ml : null,
    );
    final reward = await d.social.apply(id, decision, by: 'revisao');
    if (!approve) await d.socialRepo.restore(id);
    await d.audit.log(null, 'revisao_post', details: {'post': id, 'aprovado': approve});
    return jsonResponse({'ok': true, 'reward': reward});
  });

  r.post('/admin/posts/<id>/restore', (Request req, String id) async {
    guard(req);
    await d.socialRepo.restore(id);
    return jsonResponse({'ok': true});
  });
}
