import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import '../app_deps.dart';
import '../cities.dart';
import '../http/http_utils.dart';

/// Cidade e plano do usuário da requisição (para dia local e multiplicador).
Future<(City, bool)> rewardsContext(AppDeps d, Request req) async {
  final user = await d.users.byId(userIdOf(req));
  if (user == null) throw ApiError(401, 'Sessão expirada. Entre novamente.');
  return (cityById(user['city_id'] as String?), user['plan'] == 'plus');
}

void registerRewardsRoutes(Router r, AppDeps d) {
  r.get('/rewards', (Request req) async {
    final (city, plus) = await rewardsContext(d, req);
    return jsonResponse(await d.rewards.summary(userIdOf(req), city, plus: plus));
  });

  /// Chamado quando o app abre. Idempotente no dia.
  r.post('/rewards/checkin', (Request req) async {
    final (city, plus) = await rewardsContext(d, req);
    final earned = await d.rewards.checkIn(userIdOf(req), city, plus: plus);
    return jsonResponse({'earned': earned, 'streak': await d.rewards.streakDays(userIdOf(req), city)});
  });

  r.post('/rewards/redeem', (Request req) async {
    final b = await readJson(req);
    final offerId = bodyString(b, 'offerId', max: 80);
    final (city, plus) = await rewardsContext(d, req);
    final (coupon, error) = await d.rewards.redeem(userIdOf(req), offerId, city, plus: plus);
    if (error != null) throw ApiError(409, error);
    await d.audit.log(userIdOf(req), 'cupom_resgatado', details: {'oferta': offerId});
    return jsonResponse(coupon, status: 201);
  });
}
