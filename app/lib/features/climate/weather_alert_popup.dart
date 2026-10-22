import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../../core/storage/local_store.dart';
import '../../core/theme/tokens.dart';
import 'climate_providers.dart';

/// Avisos de chuva, alagamento, temporal, sol e calor das próximas 12 horas.
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

/// Cada aviso aparece uma vez por período de 6 horas, para não repetir a
/// cada abertura do app. Guarda os últimos avisos mostrados.
class WeatherPopupLog {
  WeatherPopupLog(this._store);
  final LocalStore _store;
  static const _key = 'weather_popups_shown';

  static String keyOf(WeatherAlert a) => '${a.kind.name}@${a.at.year}-${a.at.month}-${a.at.day}-${a.at.hour ~/ 6}';

  bool shown(WeatherAlert a) => _store.readList(_key).contains(keyOf(a));

  Future<void> mark(WeatherAlert a) {
    final list = [..._store.readList(_key).where((k) => k != keyOf(a)), keyOf(a)];
    return _store.writeList(_key, list.length > 30 ? list.sublist(list.length - 30) : list);
  }
}

final weatherPopupLogProvider = Provider((ref) => WeatherPopupLog(ref.watch(localStoreProvider)));

/// Mostra o aviso mais importante que ainda não apareceu; os outros vão juntos, resumidos.
Future<void> showWeatherAlertPopup(BuildContext context, List<WeatherAlert> alerts) {
  final main = alerts.first;
  final others = alerts.skip(1).toList();
  final color = weatherAlertColor(main.kind);
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final t = Theme.of(ctx).textTheme;
      return AlertDialog(
        icon: Icon(weatherAlertIcon(main.kind), color: color, size: 40),
        title: Text(main.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(main.message, style: t.bodyLarge),
            if (others.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Também nas próximas horas', style: t.titleSmall),
              const SizedBox(height: 6),
              for (final o in others)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(weatherAlertIcon(o.kind), size: 20, color: weatherAlertColor(o.kind)),
                    const SizedBox(width: 8),
                    Expanded(child: Text('${o.title}: ${o.message}', style: t.bodyMedium)),
                  ]),
                ),
            ],
          ]),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Entendi'))],
      );
    },
  );
}

/// Fica na tela inicial: quando a previsão traz um aviso novo, abre o pop-up.
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
    ref.listenManual(weatherAlertsProvider, (_, alerts) => _maybeShow(alerts), fireImmediately: true);
  }

  void _maybeShow(List<WeatherAlert> alerts) {
    if (_open || alerts.isEmpty) return;
    final log = ref.read(weatherPopupLogProvider);
    final fresh = alerts.where((a) => !log.shown(a)).toList();
    if (fresh.isEmpty) return;
    _open = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _open = false;
        return;
      }
      for (final a in alerts) {
        await log.mark(a);
      }
      if (!mounted) return;
      // O aviso novo mais grave abre o pop-up; os outros aparecem resumidos.
      await showWeatherAlertPopup(context, [fresh.first, ...alerts.where((a) => a != fresh.first)]);
      _open = false;
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
