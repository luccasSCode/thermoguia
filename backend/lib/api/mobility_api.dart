import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../app_deps.dart';
import '../cities.dart';
import '../http/http_utils.dart';
import 'rewards_api.dart';
import '../services/routing_service.dart';

Future<City> _cityOf(AppDeps d, Request req) async {
  final user = await d.users.byId(userIdOf(req));
  return cityById(user?['city_id'] as String?);
}

void _ensureInside(City city, GeoPoint p) {
  if (!city.bounds.contains(p)) {
    throw ApiError(422, 'Por enquanto o ThermoGuia atende apenas ${city.name}.');
  }
}

void registerMobilityRoutes(Router r, AppDeps d) {
  r.get('/climate', (Request req) async {
    final lat = qDouble(req, 'lat'), lng = qDouble(req, 'lng');
    final bundle = await d.weather.fetch(lat, lng);
    final sun = sunPosition(lat, lng, DateTime.now());
    return jsonResponse({
      ...bundle.toJson(),
      'sun': {'elevationDeg': sun.elevationDeg, 'azimuthDeg': sun.azimuthDeg},
    });
  });

  /// Qualidade do ar (PM2.5 e PM10) de agora e das próximas 72 horas.
  r.get('/air', (Request req) async {
    final bundle = await d.air.fetch(qDouble(req, 'lat'), qDouble(req, 'lng'));
    return jsonResponse(bundle.toJson());
  });

  /// Fumaça agora em vários pontos da cidade do usuário (mapa da aba Rotas).
  r.get('/air/map', (Request req) async {
    final city = await _cityOf(d, req);
    return jsonResponse({'points': await d.air.grid(city.bounds)});
  });

  r.post('/routes/fresh', (Request req) async {
    final b = await readJson(req);
    final city = await _cityOf(d, req);
    final origin = GeoPoint.fromJson((b['origin'] as Map).cast<String, dynamic>());
    final dest = GeoPoint.fromJson((b['destination'] as Map).cast<String, dynamic>());
    _ensureInside(city, origin);
    _ensureInside(city, dest);

    final mode = switch (b['mode']) {
      'bike' => 'bike',
      'moto' => 'moto',
      _ => 'foot',
    };
    final departAt = DateTime.tryParse('${b['departAt']}')?.toUtc() ?? DateTime.now().toUtc();
    final profile = await d.profiles.get(userIdOf(req));
    final shadePref = (b['shadePreference'] as num?)?.toDouble() ?? profile.shadePreference;

    final bundle = await d.weather.fetch(origin.lat, origin.lng);
    final climate = bundle.at(departAt);

    final pad = 0.01;
    final reports = await d.reports.inBox(
      [origin.lat, dest.lat].reduce((a, b) => a < b ? a : b) - pad,
      [origin.lng, dest.lng].reduce((a, b) => a < b ? a : b) - pad,
      [origin.lat, dest.lat].reduce((a, b) => a > b ? a : b) + pad,
      [origin.lng, dest.lng].reduce((a, b) => a > b ? a : b) + pad,
    );
    final signals = reports
        .where((x) => x['kind'] == 'sombra_boa' || x['kind'] == 'sem_sombra')
        .map((x) => CommunitySignal(
              GeoPoint((x['lat'] as num).toDouble(), (x['lng'] as num).toDouble()),
              x['kind'] == 'sombra_boa' ? 0.25 : -0.25,
            ))
        .toList();

    final routes = await d.routing[city.id]!.freshRoutes(
      origin: origin,
      destination: dest,
      mode: mode,
      departAt: departAt,
      climate: climate,
      shadePreference: shadePref,
      signals: signals,
      reports: [
        for (final x in reports)
          RouteReport(
            x['kind'] as String,
            GeoPoint((x['lat'] as num).toDouble(), (x['lng'] as num).toDouble()),
            x['note'] as String? ?? '',
          ),
      ],
    );

    final best = routes.first;
    final fastest = routes.reduce((a, b) => a.durationS <= b.durationS ? a : b);
    final saved = (fastest.sunExposureMin - best.sunExposureMin).round();
    final extra = ((best.durationS - fastest.durationS) / 60).round();
    final advice = identical(best, fastest)
        ? 'O caminho mais rápido já é o mais fresco: ${(best.shadeScore * 100).round()}% do trajeto com sombra.'
        : 'A Rota Fresca tem ${(best.shadeScore * 100).round()}% de sombra'
            '${saved > 0 ? ' e poupa cerca de $saved min de sol direto' : ''}'
            '${extra > 0 ? ', com $extra min a mais de trajeto' : ''}.';

    return jsonResponse({
      'routes': [for (var i = 0; i < routes.length; i++) routes[i].toJson(i)],
      'climate': climate.toJson(),
      'advice': advice,
      'greenIndexReady': d.green[city.id]!.ready,
    });
  });

  r.get('/geo/search', (Request req) async {
    final q = (req.url.queryParameters['q'] ?? '').trim();
    if (q.length < 3) return jsonResponse(<Object>[]);
    return jsonResponse(await d.geocoding.search(q, await _cityOf(d, req)));
  });

  r.get('/places/oasis', (Request req) async {
    final city = await _cityOf(d, req);
    final from = GeoPoint(qDouble(req, 'lat'), qDouble(req, 'lng'));
    final list = d.green[city.id]!.nearestOases(from, limit: qInt(req, 'limit', 20).clamp(1, 50));
    return jsonResponse([
      for (final (o, dist) in list)
        {
          'id': o.id,
          'kind': o.kind,
          'name': o.name,
          'lat': o.point.lat,
          'lng': o.point.lng,
          'distanceM': dist.round(),
        }
    ]);
  });

  r.get('/reports', (Request req) async {
    final lat = qDouble(req, 'lat'), lng = qDouble(req, 'lng');
    const pad = 0.02;
    return jsonResponse(await d.reports.inBox(lat - pad, lng - pad, lat + pad, lng + pad));
  });

  r.post('/reports', (Request req) async {
    final b = await readJson(req);
    final kind = bodyString(b, 'kind', max: 40);
    if (!ReportKinds.all.contains(kind)) throw ApiError(400, 'Tipo de relato inválido.');
    final p = GeoPoint(bodyDouble(b, 'lat'), bodyDouble(b, 'lng'));
    _ensureInside(await _cityOf(d, req), p);
    final note = (b['note'] as String? ?? '').trim();
    final created = await d.reports.add(
      userIdOf(req),
      kind,
      p.lat,
      p.lng,
      note.length > 280 ? note.substring(0, 280) : note,
    );
    final (city, plus) = await rewardsContext(d, req);
    final reward = await d.rewards.award(userIdOf(req), 'relato', city, plus: plus, ref: '${created['id']}');
    return jsonResponse({...created, if (reward != null) 'reward': reward}, status: 201);
  });
}

abstract final class ReportKinds {
  static const all = {'sombra_boa', 'sem_sombra', 'bebedouro', 'calor_extremo', 'alagamento', 'transito', 'obra', 'fumaca'};
}
