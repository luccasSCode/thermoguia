import 'heat_index.dart';
import 'models.dart';
import 'risk_engine.dart';

class ComfortWindow {
  const ComfortWindow({
    required this.start,
    required this.end,
    required this.avgHeatIndexC,
    required this.level,
  });

  final DateTime start;
  final DateTime end;
  final double avgHeatIndexC;
  final RiskLevel level;

  String get rangeLabel => '${start.hour}h–${end.hour}h';
}

/// Penaliza UV alto: o mesmo índice de calor sob sol forte é pior.
double _hourCost(HourlyPoint h) =>
    heatIndexC(h.temperatureC, h.humidity) + h.uvIndex * 0.35;

/// Melhores janelas para atividades ao ar livre nas próximas 24h.
List<ComfortWindow> bestOutdoorWindows(
  List<HourlyPoint> hourly, {
  required DateTime now,
  int windowHours = 2,
  int minHour = 6,
  int maxHour = 19,
  int take = 3,
}) =>
    _windows(hourly, now, windowHours, minHour, maxHour, take, best: true);

/// Período mais crítico do dia (para o aviso "Evite sair entre...").
ComfortWindow? worstWindow(List<HourlyPoint> hourly, {required DateTime now}) {
  final w = _windows(hourly, now, 3, 8, 18, 1, best: false);
  return w.isEmpty ? null : w.first;
}

List<ComfortWindow> _windows(
  List<HourlyPoint> hourly,
  DateTime now,
  int size,
  int minHour,
  int maxHour,
  int take, {
  required bool best,
}) {
  final start = DateTime(now.year, now.month, now.day, now.hour);
  final horizon = start.add(const Duration(hours: 24));
  final pts = hourly
      .where((h) => !h.time.isBefore(start) && h.time.isBefore(horizon))
      .toList()
    ..sort((a, b) => a.time.compareTo(b.time));

  final candidates = <ComfortWindow>[];
  for (var i = 0; i + size <= pts.length; i++) {
    final slice = pts.sublist(i, i + size);
    final first = slice.first.time;
    final lastHour = slice.last.time.hour;
    if (first.hour < minHour || lastHour >= maxHour) continue;
    if (slice.last.time.difference(first).inHours != size - 1) continue;
    final avg = slice.map(_hourCost).reduce((a, b) => a + b) / size;
    candidates.add(ComfortWindow(
      start: first,
      end: first.add(Duration(hours: size)),
      avgHeatIndexC: avg,
      level: const RiskEngine().levelFor(avg),
    ));
  }
  candidates.sort((a, b) => best
      ? a.avgHeatIndexC.compareTo(b.avgHeatIndexC)
      : b.avgHeatIndexC.compareTo(a.avgHeatIndexC));

  final picked = <ComfortWindow>[];
  for (final c in candidates) {
    final overlaps = picked.any((p) => c.start.isBefore(p.end) && p.start.isBefore(c.end));
    if (!overlaps) picked.add(c);
    if (picked.length == take) break;
  }
  picked.sort((a, b) => a.start.compareTo(b.start));
  return picked;
}
