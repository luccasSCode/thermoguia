import 'package:test/test.dart';
import 'package:thermo_core/thermo_core.dart';

/// Previsão horária a partir de [start], uma concentração de PM2.5 por hora.
List<AirPoint> _air(DateTime start, List<double> pm25) => [
      for (var i = 0; i < pm25.length; i++)
        AirPoint(time: start.add(Duration(hours: i)), pm25: pm25[i], pm10: pm25[i] * 1.3),
    ];

List<HourlyPoint> _heat(DateTime start, int hours, {double t = 30}) => [
      for (var i = 0; i < hours; i++)
        HourlyPoint(time: start.add(Duration(hours: i)), temperatureC: t, humidity: 60, uvIndex: 0, precipitationProb: 0),
    ];

void main() {
  test('índice segue as faixas do CONAMA para PM2.5', () {
    expect(airLevelFor(airIndex(10, 0)), AirLevel.boa);
    expect(airLevelFor(airIndex(40, 0)), AirLevel.moderada);
    expect(airLevelFor(airIndex(60, 0)), AirLevel.ruim);
    expect(airLevelFor(airIndex(100, 0)), AirLevel.muitoRuim);
    expect(airLevelFor(airIndex(200, 0)), AirLevel.pessima);
    expect(airIndex(25, 0), 40);
    expect(airIndex(50, 0), 80);
  });

  test('o pior poluente define o índice', () {
    expect(airIndex(5, 160), greaterThan(airIndex(5, 20)));
    expect(airLevelFor(airIndex(5, 160)), AirLevel.muitoRuim);
  });

  test('22 µg/m³ por um dia equivalem a um cigarro; quem pedala respira mais', () {
    expect(cigarettesFor(22), closeTo(1, 0.001));
    expect(cigarettesFor(44, hours: 12), closeTo(1, 0.001));
    expect(breathingFactor(Persona.ciclista), greaterThan(breathingFactor(Persona.pedestre)));
  });

  test('máscara a partir de ar ruim; idoso já no moderado', () {
    expect(adviseAir(AirLevel.boa, Persona.pedestre).mask, isFalse);
    expect(adviseAir(AirLevel.moderada, Persona.pedestre).mask, isFalse);
    expect(adviseAir(AirLevel.moderada, Persona.idoso).mask, isTrue);
    expect(adviseAir(AirLevel.ruim, Persona.pedestre).mask, isTrue);
    expect(adviseAir(AirLevel.ruim, Persona.ciclista).message, contains('ônibus'));
  });

  test('Hora Segura junta horas seguidas de ar limpo e calor suportável', () {
    final start = DateTime(2026, 10, 18, 6);
    // 6h–8h limpo, 9h–14h fumaça, 15h–17h limpo.
    final air = _air(start, [10, 12, 15, 60, 70, 80, 90, 70, 60, 20, 18, 15, 60, 60]);
    final w = safeOutdoorWindows(air, _heat(start, 14), now: start);
    expect(w, hasLength(2));
    expect(w.first.rangeLabel, '6h–9h');
    expect(w.last.rangeLabel, '15h–18h');
  });

  test('sem Hora Segura quando o calor passa do limite', () {
    final start = DateTime(2026, 10, 18, 10);
    final w = safeOutdoorWindows(_air(start, List.filled(6, 10)), _heat(start, 6, t: 40), now: start);
    expect(w, isEmpty);
  });

  test('avisa 1 hora antes da fumaça e quando o ar melhora', () {
    final now = DateTime(2026, 10, 18, 7, 10);
    final air = _air(DateTime(2026, 10, 18, 7), [10, 10, 10, 80, 80, 80, 15, 15]);
    final alerts = planAirAlerts(air, now: now, persona: Persona.pedestre);
    expect(alerts, hasLength(2));
    expect(alerts.first.kind, AirAlertKind.piora);
    expect(alerts.first.at, DateTime(2026, 10, 18, 9));
    expect(alerts.first.body, contains('PFF2'));
    expect(alerts.last.kind, AirAlertKind.melhora);
    expect(alerts.last.at, DateTime(2026, 10, 18, 13));
  });

  test('de madrugada o aviso espera as 6h e some se a fumaça já passou', () {
    final now = DateTime(2026, 10, 18, 20);
    // Fumaça das 23h às 2h; às 6h o ar está limpo: nenhum aviso noturno.
    final air = _air(DateTime(2026, 10, 18, 21), [10, 10, 80, 80, 80, 80, 10, 10, 10, 10, 10, 10]);
    expect(planAirAlerts(air, now: now, persona: Persona.pedestre), isEmpty);

    // Fumaça que começa às 3h e continua de manhã: aviso às 6h.
    final air2 = _air(DateTime(2026, 10, 18, 21), [10, 10, 10, 10, 10, 10, 80, 80, 80, 80, 80, 80]);
    final alerts = planAirAlerts(air2, now: now, persona: Persona.pedestre);
    expect(alerts.single.at, DateTime(2026, 10, 19, 6));
  });
}
