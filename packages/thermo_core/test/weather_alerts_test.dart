import 'package:test/test.dart';
import 'package:thermo_core/thermo_core.dart';

final _now = DateTime(2026, 10, 22, 9);

List<HourlyPoint> _day({Map<int, double> mm = const {}, Map<int, double> prob = const {}, Map<int, int> code = const {}, double temp = 31, double uv = 5}) => [
      for (var i = 0; i < 14; i++)
        HourlyPoint(
          time: _now.add(Duration(hours: i)),
          temperatureC: temp,
          humidity: 60,
          uvIndex: _now.hour + i >= 18 ? 0 : uv,
          precipitationProb: prob[_now.hour + i] ?? 10,
          precipitationMm: mm[_now.hour + i] ?? 0,
          weatherCode: code[_now.hour + i],
        ),
    ];

void main() {
  test('tempo firme e ameno não gera aviso', () {
    expect(forecastAlerts(_day(), now: _now), isEmpty);
  });
  test('muita chuva em 3 horas → risco de alagamento, com a hora', () {
    final a = forecastAlerts(_day(mm: {15: 12, 16: 14, 17: 8}, prob: {15: 90, 16: 90, 17: 80}), now: _now);
    expect(a.first.kind, WeatherAlertKind.alagamento);
    expect(a.first.message, contains('às 15h'));
    expect(a.first.message, contains('199'));
  });
  test('trovoada provável → temporal', () {
    final a = forecastAlerts(_day(prob: {14: 70}, code: {14: 95}), now: _now);
    expect(a.first.kind, WeatherAlertKind.tempestade);
  });
  test('pancada forte → chuva forte; chuva provável → vai chover', () {
    expect(forecastAlerts(_day(mm: {13: 9}, prob: {13: 80}), now: _now).first.kind, WeatherAlertKind.chuvaForte);
    expect(forecastAlerts(_day(prob: {12: 70}), now: _now).first.kind, WeatherAlertKind.chuva);
  });
  test('só um aviso de chuva por vez (o mais grave)', () {
    final a = forecastAlerts(_day(mm: {15: 25}, prob: {12: 70, 15: 90}, code: {15: 95}), now: _now);
    expect(a.where((x) => x.kind.isRain), hasLength(1));
    expect(a.first.kind, WeatherAlertKind.alagamento);
  });
  test('sol forte e calor extremo no tempo seco', () {
    final a = forecastAlerts(_day(temp: 36, uv: 11), now: _now).map((x) => x.kind).toList();
    expect(a, containsAll([WeatherAlertKind.calorExtremo, WeatherAlertKind.solForte]));
  });

  group('notificações chegam antes da previsão', () {
    test('cada aviso com a antecedência do seu tipo', () {
      final n = planWeatherNotices(_day(mm: {15: 12, 16: 14, 17: 8}, prob: {15: 90, 16: 90, 17: 80}, temp: 36, uv: 11), now: _now);
      final flood = n.firstWhere((x) => x.kind == WeatherAlertKind.alagamento);
      expect(flood.notifyAt, DateTime(2026, 10, 22, 12)); // 3 h antes das 15h
      expect(flood.title, 'Risco de alagamento às 15h');
      expect(flood.body, startsWith('Daqui a cerca de 3 horas.'));
    });
    test('se a antecedência já passou, avisa agora', () {
      final n = planWeatherNotices(_day(prob: {10: 70}), now: _now);
      expect(n.single.kind, WeatherAlertKind.chuva);
      expect(n.single.notifyAt, _now);
    });
    test('evento em menos de 20 minutos não vira notificação', () {
      expect(planWeatherNotices(_day(prob: {9: 70}), now: _now.add(const Duration(minutes: 45))), isEmpty);
    });
    test('avisos comuns respeitam a noite; alagamento toca a qualquer hora', () {
      final night = DateTime(2026, 10, 22, 21);
      List<HourlyPoint> at(int hour, {double mm = 0, double prob = 70}) => [
            for (var i = 0; i < 14; i++)
              HourlyPoint(
                time: night.add(Duration(hours: i)),
                temperatureC: 26,
                humidity: 80,
                uvIndex: 0,
                precipitationProb: (night.add(Duration(hours: i)).hour == hour) ? prob : 10,
                precipitationMm: (night.add(Duration(hours: i)).hour == hour) ? mm : 0,
              ),
          ];
      // Chuva às 7h: o aviso iria às 6h... fica às 6h. Chuva às 3h: não toca.
      final morning = planWeatherNotices(at(7), now: night).single;
      expect(morning.notifyAt, DateTime(2026, 10, 23, 6));
      expect(morning.body, contains('às 7h'));
      expect(morning.body, isNot(contains('amanhã')));
      expect(planWeatherNotices(at(3), now: night), isEmpty);
      // Alagamento às 2h: toca às 23h.
      final flood = planWeatherNotices(at(2, mm: 25, prob: 90), now: night).single;
      expect(flood.kind, WeatherAlertKind.alagamento);
      expect(flood.notifyAt, DateTime(2026, 10, 22, 23));
      expect(flood.title, 'Risco de alagamento amanhã às 2h');
    });
  });
}
