import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/features/air/air_card.dart';
import 'package:thermoguia/features/air/air_providers.dart';
import 'package:thermoguia/features/air/air_repository.dart';
import 'package:thermoguia/features/session/presentation/session_controller.dart';

/// Fumaça como a de Manaus em outubro de 2026: PM2.5 acima de 100 de noite,
/// melhorando à tarde.
AirData _smoke(DateTime now) {
  final start = DateTime(now.year, now.month, now.day, now.hour);
  const pm = <double>[114, 120, 133, 150, 173, 166, 150, 120, 90, 65, 49, 40, 35, 30, 45, 64, 70, 90, 110, 130, 140, 120, 100, 80];
  final hourly = [
    for (var i = 0; i < pm.length; i++) AirPoint(time: start.add(Duration(hours: i)), pm25: pm[i], pm10: pm[i] * 1.02),
  ];
  return AirData(current: hourly.first, hourly: hourly, fetchedAt: now);
}

class _FakeAir extends AirController {
  _FakeAir(this.data);
  final AirData data;

  @override
  Future<AirData> build() async => data;
}

void main() {
  test('alerta imediato: avisa ao piorar, repete após 6 h e avisa quando o ar melhora', () {
    final now = DateTime(2026, 10, 18, 12);
    final advice = adviseAir(AirLevel.muitoRuim, Persona.pedestre);
    AirLevel? last;
    DateTime? lastAt;
    ({String title, String body})? check(AirLevel level, DateTime at) =>
        airAlertNow(level: level, advice: adviseAir(level, Persona.pedestre), lastLevel: last, lastAt: lastAt, now: at);

    expect(check(AirLevel.boa, now), isNull);
    expect(check(AirLevel.muitoRuim, now)!.title, contains('Alerta de fumaça'));
    expect(check(AirLevel.muitoRuim, now)!.body, contains(advice.title));

    last = AirLevel.muitoRuim;
    lastAt = now;
    expect(check(AirLevel.muitoRuim, now.add(const Duration(hours: 2))), isNull);
    expect(check(AirLevel.ruim, now.add(const Duration(hours: 2))), isNull);
    expect(check(AirLevel.pessima, now.add(const Duration(hours: 2))), isNotNull);
    expect(check(AirLevel.muitoRuim, now.add(const Duration(hours: 6))), isNotNull);
    expect(check(AirLevel.moderada, now.add(const Duration(hours: 1)))!.title, 'O ar melhorou: pode sair');
  });

  for (final dark in [false, true]) {
    testWidgets('card do ar cabe na tela do celular (${dark ? 'escuro' : 'claro'})', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final now = DateTime.now();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          airProvider.overrideWith(() => _FakeAir(_smoke(now))),
          personaProvider.overrideWithValue(Persona.ciclista),
          safeWindowsProvider.overrideWithValue([
            SafeWindow(start: DateTime(2026, 10, 18, 15), end: DateTime(2026, 10, 18, 17), airIndex: 60, feelsC: 33),
          ]),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const Scaffold(body: SingleChildScrollView(child: AirQualityCard())),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Muito ruim'), findsOneWidget);
      expect(find.textContaining('cigarros'), findsOneWidget);
      expect(find.textContaining('2,0× mais ar'), findsOneWidget);
      expect(find.text('Hora Segura:'), findsOneWidget);
      expect(find.text('15h–17h · 33°'), findsOneWidget);

      await tester.tap(find.text('Como se proteger da fumaça'));
      await tester.pumpAndSettle();
      expect(find.text('Fumaça e qualidade do ar'), findsOneWidget);
    });
  }
}
