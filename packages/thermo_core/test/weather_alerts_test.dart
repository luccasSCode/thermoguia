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
}
