import 'package:test/test.dart';
import 'package:thermo_core/thermo_core.dart';

ClimateSnapshot _climate({double t = 33, double rh = 65, double uv = 10}) => ClimateSnapshot(
      time: DateTime(2026, 10, 13, 12),
      temperatureC: t,
      humidity: rh,
      apparentC: t + 4,
      uvIndex: uv,
      windKmh: 5,
      precipitationProb: 10,
      cloudCover: 20,
      isDay: true,
    );

void main() {
  test('índice de calor aumenta com a umidade', () {
    expect(heatIndexC(33, 80), greaterThan(heatIndexC(33, 40)));
  });

  test('índice de calor ≈ temperatura em clima ameno', () {
    expect(heatIndexC(22, 50), closeTo(22, 1.5));
  });

  test('entregador ao meio-dia em Manaus tem risco alto ou pior', () {
    final r = const RiskEngine().assess(
      _climate(),
      const UserContext(persona: Persona.entregador, exposureMinutesToday: 120),
    );
    expect(r.level.index, greaterThanOrEqualTo(RiskLevel.muitoAlto.index));
    expect(r.recommendations, isNotEmpty);
  });

  test('feedback de muito calor aumenta a sensibilidade', () {
    const p = AdaptiveProfile();
    final next = p.withComfortFeedback(ComfortFeedback.muitoCalor, RiskLevel.moderado);
    expect(next.sensitivityOffset, greaterThan(0));
  });

  test('escolher rota mais longa e sombreada aumenta a preferência por sombra', () {
    const p = AdaptiveProfile(shadePreference: 0.5);
    final next = p.withRouteChoice(chosenShade: 0.7, fastestShade: 0.3, chosenDurationRatio: 1.2);
    expect(next.shadePreference, greaterThan(0.5));
  });

  test('sol ao meio-dia em Manaus está alto', () {
    // 12h local = 16h UTC
    final s = sunPosition(-3.1, -60.0, DateTime.utc(2026, 10, 13, 16));
    expect(s.elevationDeg, greaterThan(60));
  });

  test('melhores janelas evitam o meio-dia', () {
    final base = DateTime(2026, 10, 13, 6);
    final hourly = List.generate(24, (i) {
      final h = (6 + i) % 24;
      final hot = h >= 10 && h <= 15;
      return HourlyPoint(
        time: base.add(Duration(hours: i)),
        temperatureC: hot ? 35 : 27,
        humidity: 70,
        uvIndex: hot ? 11 : 2,
        precipitationProb: 0,
      );
    });
    final w = bestOutdoorWindows(hourly, now: base);
    expect(w.every((x) => x.start.hour < 10 || x.start.hour >= 16), isTrue);
  });
}
