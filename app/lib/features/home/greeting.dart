import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Períodos do dia usados na saudação da tela inicial.
enum DayPeriod {
  madrugada('Boa madrugada', 0),
  manha('Bom dia', 6),
  tarde('Boa tarde', 12),
  noite('Boa noite', 18);

  const DayPeriod(this.greeting, this.startHour);
  final String greeting;
  final int startHour;

  /// Madrugada 00:00–05:59, manhã 06:00–11:59, tarde 12:00–17:59,
  /// noite 18:00–23:59.
  static DayPeriod of(DateTime t) => values.lastWhere((p) => t.hour >= p.startHour);

  /// Quando começa o período seguinte a [t].
  static DateTime nextChange(DateTime t) {
    final next = values.firstWhere((p) => p.startHour > t.hour, orElse: () => madrugada);
    final day = DateTime(t.year, t.month, t.day);
    return next == madrugada ? DateTime(t.year, t.month, t.day + 1) : day.add(Duration(hours: next.startHour));
  }
}

/// Período atual. Se recalcula sozinho na virada (ex.: às 12:00 passa de
/// "Bom dia" para "Boa tarde" mesmo com o app aberto).
final dayPeriodProvider = Provider<DayPeriod>((ref) {
  final now = DateTime.now();
  final timer = Timer(DayPeriod.nextChange(now).difference(now), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return DayPeriod.of(now);
});
