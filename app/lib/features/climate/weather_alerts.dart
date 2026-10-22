import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../../core/services/notification_inbox.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/tokens.dart';
import 'climate_providers.dart';

/// Avisos de chuva, alagamento, temporal, sol e calor das próximas 12 horas
/// (o bloco "Próximas horas" da tela inicial).
final weatherAlertsProvider = Provider<List<WeatherAlert>>((ref) {
  final climate = ref.watch(climateProvider).valueOrNull;
  if (climate == null || climate.stale) return const [];
  return forecastAlerts(climate.hourly, now: DateTime.now());
});

IconData weatherAlertIcon(WeatherAlertKind k) => switch (k) {
      WeatherAlertKind.alagamento => Icons.flood_outlined,
      WeatherAlertKind.tempestade => Icons.thunderstorm_outlined,
      WeatherAlertKind.chuvaForte => Icons.water_drop_outlined,
      WeatherAlertKind.chuva => Icons.umbrella_outlined,
      WeatherAlertKind.calorExtremo => Icons.local_fire_department_outlined,
      WeatherAlertKind.solForte => Icons.wb_sunny_outlined,
    };

Color weatherAlertColor(WeatherAlertKind k) => switch (k) {
      WeatherAlertKind.alagamento || WeatherAlertKind.tempestade => const Color(0xFFA8231F),
      WeatherAlertKind.chuvaForte || WeatherAlertKind.chuva => Tokens.rio,
      WeatherAlertKind.calorExtremo => const Color(0xFFD9542B),
      WeatherAlertKind.solForte => Tokens.sol,
    };

// ---------- notificações com antecedência ----------

/// Ids reservados para os avisos de previsão programados.
const _idBase = 300;
const _idCount = 12;

/// Quando cada evento foi (ou será) avisado, pela chave do evento. Evita
/// avisar de novo a mesma chuva quando a previsão é atualizada.
class WeatherNoticeLog {
  WeatherNoticeLog(this._store);
  final LocalStore _store;
  static const _key = 'weather_notices';

  Map<String, DateTime> read() => {
        for (final e in (_store.readMap(_key) ?? const {}).entries)
          if (DateTime.tryParse('${e.value}') case final t?) e.key: t,
      };

  Future<void> write(Map<String, DateTime> log) {
    final cutoff = DateTime.now().subtract(const Duration(days: 2));
    return _store.writeMap(_key, {
      for (final e in log.entries)
        if (e.value.isAfter(cutoff)) e.key: e.value.toIso8601String(),
    });
  }
}

final weatherNoticeLogProvider = Provider((ref) => WeatherNoticeLog(ref.watch(localStoreProvider)));

/// Refaz as notificações de previsão das próximas 24 horas. Cada aviso toca
/// com a antecedência do seu tipo (3 h antes do alagamento, 2 h antes do
/// temporal, da chuva forte e do calor extremo, 1 h antes da chuva e do sol
/// forte). Um aviso que já tocou não toca de novo.
Future<void> rescheduleWeatherNotices(Ref ref) async {
  final svc = ref.read(notificationServiceProvider);
  final climate = ref.read(climateProvider).valueOrNull;
  if (climate == null || climate.stale) return;
  await svc.cancelRange(_idBase, _idBase + _idCount - 1);
  if (!svc.enabled(NotifKind.tempo)) return;

  final now = DateTime.now();
  final logStore = ref.read(weatherNoticeLogProvider);
  final log = logStore.read();
  var id = _idBase;
  for (final n in planWeatherNotices(climate.hourly, now: now)) {
    if (id >= _idBase + _idCount) break;
    final sent = log[n.key];
    if (sent != null && !sent.isAfter(now)) continue;
    // "Agora" vira alguns segundos à frente: o sistema não programa no passado.
    final at = n.notifyAt.isAfter(now) ? n.notifyAt : now.add(const Duration(seconds: 5));
    await svc.schedule(id++, at, n.title, n.body, route: '/agora', kind: NotifKind.tempo);
    log[n.key] = at;
  }
  await logStore.write(log);
}

/// Para widgets: `ref.read(weatherNoticesSchedulerProvider)()`.
final weatherNoticesSchedulerProvider = Provider((ref) => () => rescheduleWeatherNotices(ref));

// ---------- pop-up só para risco à vida ----------

/// Pop-ups já mostrados (chave do evento), para não repetir.
class WeatherPopupLog {
  WeatherPopupLog(this._store);
  final LocalStore _store;
  static const _key = 'weather_popups_shown';

  bool shown(WeatherNotice n) => _store.readList(_key).contains(n.key);

  Future<void> mark(WeatherNotice n) {
    final list = [..._store.readList(_key).where((k) => k != n.key), n.key];
    return _store.writeList(_key, list.length > 30 ? list.sublist(list.length - 30) : list);
  }
}

final weatherPopupLogProvider = Provider((ref) => WeatherPopupLog(ref.watch(localStoreProvider)));

/// Alagamento ou temporal nas próximas 6 horas que ainda não viraram pop-up.
final urgentWeatherProvider = Provider<WeatherNotice?>((ref) {
  final climate = ref.watch(climateProvider).valueOrNull;
  if (climate == null || climate.stale) return null;
  final now = DateTime.now();
  final log = ref.read(weatherPopupLogProvider);
  return planWeatherNotices(climate.hourly, now: now, hours: 6)
      .where((n) => n.kind.urgent && !log.shown(n))
      .firstOrNull;
});

/// Detalhes de um aviso (também usado ao tocar no bloco "Próximas horas").
Future<void> showWeatherAlertDialog(BuildContext context, WeatherAlert alert) {
  final color = weatherAlertColor(alert.kind);
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(weatherAlertIcon(alert.kind), color: color, size: 40),
      title: Text(alert.title),
      content: SingleChildScrollView(child: Text(alert.message, style: Theme.of(ctx).textTheme.bodyLarge)),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
    ),
  );
}

/// Fica na tela inicial: abre o pop-up só para alagamento e temporal. Os
/// outros avisos chegam como notificação e aparecem em "Próximas horas".
class WeatherAlertWatcher extends ConsumerStatefulWidget {
  const WeatherAlertWatcher({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<WeatherAlertWatcher> createState() => _WeatherAlertWatcherState();
}

class _WeatherAlertWatcherState extends ConsumerState<WeatherAlertWatcher> {
  bool _open = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(urgentWeatherProvider, (_, n) => _maybeShow(n), fireImmediately: true);
  }

  void _maybeShow(WeatherNotice? n) {
    if (_open || n == null) return;
    _open = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        await ref.read(weatherPopupLogProvider).mark(n);
        if (mounted) await showWeatherAlertDialog(context, n.alert);
      }
      _open = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
