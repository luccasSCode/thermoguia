import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:test/test.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:thermoguia_backend/cities.dart';
import 'package:thermoguia_backend/config.dart';
import 'package:thermoguia_backend/http/http_utils.dart';
import 'package:thermoguia_backend/services/green_index_service.dart';
import 'package:thermoguia_backend/services/routing_service.dart';

const _centro = GeoPoint(-3.1190, -60.0217);
const _pontaNegra = GeoPoint(-3.0634, -60.1009);

/// Resposta do OSRM com uma rota de [meters] metros que levaria [seconds] de carro.
String _ok(double meters, double seconds) => jsonEncode({
      'code': 'Ok',
      'routes': [
        {
          'distance': meters,
          'duration': seconds,
          'geometry': {
            'coordinates': [
              [_centro.lng, _centro.lat],
              [-60.0600, -3.0900],
              [_pontaNegra.lng, _pontaNegra.lat],
            ],
          },
          'legs': [
            {
              'steps': [
                {
                  'name': 'Avenida Coronel Teixeira',
                  'maneuver': {'type': 'depart', 'location': [_centro.lng, _centro.lat]},
                },
                {
                  'name': '',
                  'maneuver': {'type': 'arrive', 'location': [_pontaNegra.lng, _pontaNegra.lat]},
                },
              ],
            },
          ],
        },
      ],
    });

final _noRoute = jsonEncode({'code': 'NoRoute', 'message': 'Impossible route between points'});

ClimateSnapshot _climate() => ClimateSnapshot(
      time: DateTime.utc(2026, 10, 18, 15),
      temperatureC: 34,
      humidity: 60,
      apparentC: 40,
      uvIndex: 9,
      windKmh: 5,
      precipitationProb: 0,
      cloudCover: 20,
      isDay: true,
    );

Future<List<FreshRoute>> _route(http.Client client, {String mode = 'foot'}) {
  final config = Config.defaults();
  return RoutingService(config, client, GreenIndexService(config, client, manaus)).freshRoutes(
    origin: _centro,
    destination: _pontaNegra,
    mode: mode,
    departAt: DateTime.utc(2026, 10, 18, 15),
    climate: _climate(),
    shadePreference: 0.5,
  );
}

void main() {
  test('sem caminho a pé mapeado (Ponta Negra), usa as ruas de carro no tempo de caminhada', () async {
    final asked = <String>[];
    final routes = await _route(MockClient((req) async {
      asked.add(req.url.path);
      return req.url.path.contains('routed-car')
          ? http.Response(_ok(12600, 900), 200)
          : http.Response(_noRoute, 400);
    }));

    expect(asked.first, contains('routed-foot'));
    expect(asked, contains(contains('routed-car')));
    expect(routes, isNotEmpty);
    expect(routes.every((r) => r.approximate), isTrue);
    // 12,6 km a 1,3 m/s ≈ 2 h 41 min, não os 15 min do carro.
    expect(routes.first.durationS, closeTo(12600 / RoutingService.walkSpeedMs, 1));
    expect(routes.first.toJson(0)['approximate'], isTrue);
  });

  test('de bicicleta, o plano B usa a velocidade da bicicleta', () async {
    final routes = await _route(
      MockClient((req) async => req.url.path.contains('routed-car')
          ? http.Response(_ok(12600, 900), 200)
          : http.Response(_noRoute, 400)),
      mode: 'bike',
    );
    expect(routes.first.durationS, closeTo(12600 / RoutingService.bikeSpeedMs, 1));
  });

  test('com caminho a pé, não usa o plano B', () async {
    final asked = <String>[];
    final routes = await _route(MockClient((req) async {
      asked.add(req.url.path);
      return http.Response(_ok(11000, 8500), 200);
    }));
    expect(asked.every((p) => p.contains('routed-foot')), isTrue);
    expect(routes.first.approximate, isFalse);
    expect(routes.first.durationS, 8500);
  });

  test('moto (entregador) vai direto pelas ruas, no tempo da própria malha e sem aviso de aproximação', () async {
    final asked = <String>[];
    final routes = await _route(
      MockClient((req) async {
        asked.add(req.url.path);
        return http.Response(_ok(12600, 900), 200);
      }),
      mode: 'moto',
    );
    expect(asked.every((p) => p.contains('routed-car')), isTrue);
    expect(routes.first.approximate, isFalse);
    expect(routes.first.durationS, 900);
  });

  test('nem de carro há caminho: "não encontramos", e não "serviço indisponível"', () async {
    await expectLater(
      _route(MockClient((_) async => http.Response(_noRoute, 400))),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 404)),
    );
  });

  test('servidor de rotas fora do ar continua como "indisponível"', () async {
    await expectLater(
      _route(MockClient((_) async => http.Response('Bad Gateway', 502))),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 503)),
    );
  });
}
