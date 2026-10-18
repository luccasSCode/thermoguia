import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../../core/services/location_service.dart';
import '../climate/climate_providers.dart';
import '../session/presentation/session_controller.dart';
import 'air_repository.dart';

final airRepositoryProvider = Provider(
  (ref) => AirRepository(ref.watch(apiClientProvider), ref.watch(localStoreProvider)),
);

/// Qualidade do ar no local do usuário, atualizada a cada 15 minutos.
class AirController extends AsyncNotifier<AirData> {
  Timer? _timer;

  @override
  Future<AirData> build() async {
    final loc = await ref.watch(userLocationProvider.future);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 15), (_) => refresh());
    ref.onDispose(() => _timer?.cancel());
    return ref.read(airRepositoryProvider).fetch(loc.point);
  }

  Future<void> refresh() async {
    final loc = ref.read(userLocationProvider).valueOrNull ?? UserLocation.fallback;
    final next = await AsyncValue.guard(() => ref.read(airRepositoryProvider).fetch(loc.point));
    // Falha passageira não apaga o card que já está na tela.
    if (next.hasValue || !state.hasValue) state = next;
  }
}

final airProvider = AsyncNotifierProvider<AirController, AirData>(AirController.new);

/// Recomendação para o ar de agora, ajustada ao perfil.
final airAdviceProvider = Provider<AirAdvice?>((ref) {
  final air = ref.watch(airProvider).valueOrNull;
  if (air == null) return null;
  return adviseAir(air.current.level, ref.watch(personaProvider));
});

/// Hora Segura: ar limpo e calor suportável ao mesmo tempo.
final safeWindowsProvider = Provider<List<SafeWindow>>((ref) {
  final air = ref.watch(airProvider).valueOrNull;
  final climate = ref.watch(climateProvider).valueOrNull;
  if (air == null) return const [];
  return safeOutdoorWindows(air.hourly, climate?.hourly ?? const [], now: DateTime.now());
});

/// Alertas de qualidade do ar (ligados por padrão), salvos no aparelho.
class AirAlertsSetting extends Notifier<bool> {
  static const key = 'notif_ar';

  @override
  bool build() => ref.read(localStoreProvider).getString(key) != '0';

  Future<void> set(bool on) async {
    state = on;
    await ref.read(localStoreProvider).setString(key, on ? '1' : '0');
    await rescheduleAirAlerts(ref);
  }
}

final airAlertsSettingProvider = NotifierProvider<AirAlertsSetting, bool>(AirAlertsSetting.new);

/// Ids reservados para os alertas de ar programados.
const _idBase = 200;
const _idCount = 20;
const _lastKey = 'air_last_alert';

/// Decide se o ar de agora merece notificação imediata. Avisa quando a fumaça
/// chega ou piora de faixa, repete a cada 6 horas se continuar ruim e avisa
/// uma vez quando o ar volta a ficar bom. Puro, para testar.
({String title, String body})? airAlertNow({
  required AirLevel level,
  required AirAdvice advice,
  required AirLevel? lastLevel,
  required DateTime? lastAt,
  required DateTime now,
}) {
  final wasBad = lastLevel?.isBad ?? false;
  if (level.isBad) {
    final worse = lastLevel == null || level.index > lastLevel.index;
    final stale = lastAt == null || now.difference(lastAt).inHours >= 6;
    if (!worse && !stale) return null;
    return (
      title: level.index >= AirLevel.muitoRuim.index
          ? 'Alerta de fumaça: qualidade do ar ${level.label.toLowerCase()}'
          : 'Fumaça no ar agora',
      body: '${advice.title}. ${advice.message}',
    );
  }
  if (wasBad) {
    return (
      title: 'O ar melhorou: pode sair',
      body: 'A qualidade do ar está ${level.label.toLowerCase()}. Boa hora para sair e abrir as janelas.',
    );
  }
  return null;
}

/// Chamado a cada atualização do ar: avisa o que está acontecendo agora e
/// refaz os avisos programados com a previsão nova.
Future<void> onAirUpdated(Ref ref) async {
  final air = ref.read(airProvider).valueOrNull;
  if (air == null || air.stale || !ref.read(airAlertsSettingProvider)) return;
  final store = ref.read(localStoreProvider);
  final last = store.readMap(_lastKey);
  final level = air.current.level;
  final alert = airAlertNow(
    level: level,
    advice: adviseAir(level, ref.read(personaProvider)),
    lastLevel: last == null ? null : AirLevel.fromName(last['level'] as String?),
    lastAt: DateTime.tryParse('${last?['at']}'),
    now: DateTime.now(),
  );
  if (alert != null) {
    await ref.read(notificationServiceProvider).airAlert(alert.title, alert.body);
    await store.writeMap(_lastKey, {'level': level.name, 'at': DateTime.now().toIso8601String()});
  } else if (!level.isBad && last != null) {
    await store.remove(_lastKey);
  }
  await rescheduleAirAlerts(ref);
}

/// Avisos das próximas 48 horas: antes de a fumaça chegar e quando o ar melhora.
Future<void> rescheduleAirAlerts(Ref ref) async {
  final svc = ref.read(notificationServiceProvider);
  await svc.cancelRange(_idBase, _idBase + _idCount - 1);
  final air = ref.read(airProvider).valueOrNull;
  if (air == null || !ref.read(airAlertsSettingProvider)) return;
  final plan = planAirAlerts(air.hourly, now: DateTime.now(), persona: ref.read(personaProvider), max: _idCount);
  for (var i = 0; i < plan.length; i++) {
    final a = plan[i];
    await svc.schedule(_idBase + i, a.at, a.title, a.body, route: '/agora', air: true);
  }
}

/// Para widgets: `ref.read(airUpdatedProvider)()`.
final airUpdatedProvider = Provider((ref) => () => onAirUpdated(ref));
