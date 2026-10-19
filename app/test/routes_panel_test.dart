import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/services/location_service.dart';
import 'package:thermoguia/features/air/air_providers.dart';
import 'package:thermoguia/features/climate/climate_providers.dart';
import 'package:thermoguia/features/routes/data/route_models.dart';
import 'package:thermoguia/features/routes/presentation/map_effects.dart';
import 'package:thermoguia/features/routes/presentation/map_screen.dart';
import 'package:thermoguia/features/routes/presentation/route_conditions.dart';
import 'package:thermoguia/features/routes/presentation/routes_controller.dart';
import 'package:thermoguia/features/session/presentation/session_controller.dart';

const _dest = Place(name: 'Teatro Amazonas', lat: -3.1303, lng: -60.0234);

RouteOption _route(String id, {bool recommended = false}) => RouteOption(
      id: id,
      label: recommended ? 'Mais fresca' : 'Mais rápida',
      tags: const ['Rota', 'passa pela praça'],
      recommended: recommended,
      distanceM: 1800,
      durationS: 1500,
      shadeScore: 0.6,
      sunExposureMin: 8,
      thermalLoad: 1,
      points: const [LatLng(-3.1190, -60.0217), LatLng(-3.1250, -60.0225), LatLng(-3.1303, -60.0234)],
      shade: const [1, 0.5, 0],
    );

ClimateSnapshot _climate({required double uv}) => ClimateSnapshot(
      time: DateTime(2026, 10, 18, 12),
      temperatureC: 35,
      humidity: 60,
      apparentC: 41,
      uvIndex: uv,
      windKmh: 5,
      precipitationProb: 0,
      cloudCover: 10,
      isDay: true,
    );

class _FakeRoutes extends RoutesController {
  _FakeRoutes(this.initial);
  final RoutesState initial;

  @override
  RoutesState build() => initial;
}

void main() {
  test('fumaça no caminho: só manchas ruins que encostam na rota', () {
    final route = _route('a').points;
    final map = [
      const AirMapPoint(-3.1300, -60.0230, 160, AirLevel.muitoRuim), // em cima do destino
      const AirMapPoint(-3.1300, -60.0230, 40, AirLevel.boa), // perto, mas ar bom
      const AirMapPoint(-3.0000, -59.9000, 170, AirLevel.muitoRuim), // longe da rota
    ];
    expect(smokeAlong(route, map), hasLength(1));
    expect(isStrongSun(_climate(uv: 10)), isTrue);
    expect(isStrongSun(_climate(uv: 5)), isFalse);
  });

  Future<void> pumpMap(WidgetTester tester, {Persona persona = Persona.pedestre, String mode = 'foot'}) async {
    tester.view.physicalSize = const Size(360 * 3, 740 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final routes = [_route('a', recommended: true), _route('b'), _route('c')];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        personaProvider.overrideWithValue(persona),
        userLocationProvider.overrideWith((_) async => UserLocation.fallback),
        liveLocationProvider.overrideWith((_) => const Stream.empty()),
        oasesProvider.overrideWith((_) async => const []),
        reportsProvider.overrideWith((_) async => const []),
        airMapProvider.overrideWith((_) async => const [AirMapPoint(-3.1300, -60.0230, 160, AirLevel.muitoRuim)]),
        airAtProvider.overrideWith((_, __) async => AirLevel.muitoRuim),
        routesProvider.overrideWith(() => _FakeRoutes(RoutesState(
              destination: _dest,
              mode: mode,
              result: RoutesResult(
                routes: routes,
                advice: 'A rota mais fresca leva 2 minutos a mais e tem o dobro de sombra.',
                climate: _climate(uv: 10),
                greenReady: false,
              ),
            ))),
      ],
      child: const MaterialApp(home: MapScreen()),
    ));
    // As animações repetem para sempre: avança alguns quadros em vez de esperar parar.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('com destino, avisa de fumaça e sol, anima o mapa e mostra Iniciar trajeto sem rolar', (tester) async {
    await pumpMap(tester);
    expect(find.text('A pé'), findsOneWidget);
    expect(find.text('Moto'), findsNothing);

    expect(find.text('Ar muito comprometido no destino'), findsOneWidget);
    expect(find.textContaining('Sol forte no caminho'), findsOneWidget);
    expect(find.byType(SmokeCloud), findsWidgets);
    expect(find.byType(SunGlow), findsOneWidget);

    // O botão está inteiro dentro da tela, mesmo com três rotas e os avisos.
    final button = find.text('Iniciar trajeto');
    expect(button, findsOneWidget);
    final rect = tester.getRect(button);
    expect(rect.bottom, lessThanOrEqualTo(740));
    expect(tester.widget<FilledButton>(find.ancestor(of: button, matching: find.byType(FilledButton))).onPressed,
        isNotNull);
  });

  testWidgets('entregador escolhe só entre bicicleta e moto', (tester) async {
    await pumpMap(tester, persona: Persona.entregador, mode: 'moto');
    expect(find.text('Bicicleta'), findsOneWidget);
    expect(find.text('Moto'), findsOneWidget);
    expect(find.text('A pé'), findsNothing);
  });

  test('modos por perfil', () {
    expect(travelModesFor(Persona.entregador), ['bike', 'moto']);
    for (final p in Persona.values.where((p) => p != Persona.entregador)) {
      expect(travelModesFor(p), ['foot', 'bike']);
    }
  });
}
