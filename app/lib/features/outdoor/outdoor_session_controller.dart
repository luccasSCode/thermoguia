import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../climate/climate_providers.dart';

class OutdoorState {
  const OutdoorState({
    required this.day,
    required this.minutesToday,
    this.active = false,
    this.fromTrip = false,
    this.since,
  });

  final String day;
  final int minutesToday;
  final bool active;
  final bool fromTrip;
  final DateTime? since;

  OutdoorState copyWith(
          {int? minutesToday,
          bool? active,
          bool? fromTrip,
          DateTime? since,
          bool clearSince = false}) =>
      OutdoorState(
        day: day,
        minutesToday: minutesToday ?? this.minutesToday,
        active: active ?? this.active,
        fromTrip: fromTrip ?? this.fromTrip,
        since: clearSince ? null : (since ?? this.since),
      );
}

/// "Estou na rua": contabiliza o tempo ao sol do dia e dispara
/// lembretes de hidratação no intervalo indicado pelo agente.
class OutdoorSessionController extends Notifier<OutdoorState> {
  Timer? _timer;
  DateTime? _lastReminder;
  DateTime? _lastHeatAlert;

  String _today() {
    final n = DateTime.now();
    return '${n.year}-${n.month}-${n.day}';
  }

  @override
  OutdoorState build() {
    ref.onDispose(() => _timer?.cancel());
    final saved = ref.read(localStoreProvider).readMap('outdoor_state');
    final day = _today();
    final minutes = saved != null && saved['day'] == day
        ? (saved['minutes'] as num).toInt()
        : 0;
    return OutdoorState(day: day, minutesToday: minutes);
  }

  void start({bool fromTrip = false}) {
    if (state.active) {
      if (fromTrip && !state.fromTrip) state = state.copyWith(fromTrip: true);
      return;
    }
    state =
        state.copyWith(active: true, fromTrip: fromTrip, since: DateTime.now());
    _lastReminder = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _tick());
    ref.read(notificationServiceProvider).requestPermission();
  }

  void stop() {
    _timer?.cancel();
    state = state.copyWith(active: false, fromTrip: false, clearSince: true);
  }

  void toggle() => state.active ? stop() : start();

  Future<void> _tick() async {
    if (state.day != _today()) {
      state = OutdoorState(
          day: _today(),
          minutesToday: 0,
          active: state.active,
          fromTrip: state.fromTrip,
          since: state.since);
    }
    final climate = ref.read(climateProvider).valueOrNull;
    if (climate == null || !climate.current.isDay) return;

    state = state.copyWith(minutesToday: state.minutesToday + 1);
    await ref.read(localStoreProvider).writeMap(
        'outdoor_state', {'day': state.day, 'minutes': state.minutesToday});

    final risk = ref.read(riskProvider);
    if (risk == null) return;
    final now = DateTime.now();
    if (_lastReminder == null ||
        now.difference(_lastReminder!).inMinutes >= risk.hydrationIntervalMin) {
      _lastReminder = now;
      await ref
          .read(notificationServiceProvider)
          .hydrationReminder(risk.hydrationIntervalMin);
    }
    if (risk.level == RiskLevel.extremo &&
        (_lastHeatAlert == null ||
            now.difference(_lastHeatAlert!).inMinutes >= 30)) {
      _lastHeatAlert = now;
      await ref.read(notificationServiceProvider).heatAlert(
            'Calor extremo agora',
            'Procure sombra ou um local climatizado por 15 minutos.',
          );
      await ref.read(auditLoggerProvider).log('alerta_calor_extremo', details: {
        'effectiveIndexC': risk.effectiveIndexC.toStringAsFixed(1),
        'minutesToday': state.minutesToday,
      });
    }
  }
}

final outdoorSessionProvider =
    NotifierProvider<OutdoorSessionController, OutdoorState>(
        OutdoorSessionController.new);
