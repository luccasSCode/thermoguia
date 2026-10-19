import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../../core/services/location_service.dart';
import '../adaptive/adaptive_controller.dart';
import '../hydration/hydration_controller.dart';
import '../outdoor/outdoor_session_controller.dart';
import '../session/presentation/session_controller.dart';
import 'climate_repository.dart';

final climateRepositoryProvider = Provider(
  (ref) => ClimateRepository(ref.watch(apiClientProvider), ref.watch(localStoreProvider)),
);

final userLocationProvider = FutureProvider<UserLocation>(
  (ref) => ref.watch(locationServiceProvider).current(),
);

/// Posição ao vivo, para o ponto azul do mapa. Sem permissão, não emite.
final liveLocationProvider = StreamProvider.autoDispose<GeoPoint>((ref) async* {
  final loc = await ref.watch(userLocationProvider.future);
  if (loc.isApproximate) return;
  yield loc.point;
  yield* ref.read(locationServiceProvider).track();
});

/// Clima no local do usuário, atualizado a cada 10 minutos.
class ClimateController extends AsyncNotifier<ClimateData> {
  Timer? _timer;

  @override
  Future<ClimateData> build() async {
    // O Modo Sol lê o clima já na abertura; sem conta o servidor recusa (401) e
    // o erro ficaria na tela inicial. Espera o login e busca de novo quando ele chega.
    final signedIn = ref.watch(sessionProvider.select((s) => s.status == SessionStatus.signedIn));
    if (!signedIn) return Completer<ClimateData>().future;
    final loc = await ref.watch(userLocationProvider.future);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 10), (_) => refresh(silent: true));
    ref.onDispose(() => _timer?.cancel());
    return ref.read(climateRepositoryProvider).fetch(loc.point);
  }

  Future<void> refresh({bool silent = false}) async {
    if (!silent) state = const AsyncLoading<ClimateData>().copyWithPrevious(state);
    final loc = ref.read(userLocationProvider).valueOrNull ?? UserLocation.fallback;
    state = await AsyncValue.guard(() => ref.read(climateRepositoryProvider).fetch(loc.point));
  }

  /// Pede a localização de novo (ex.: após conceder permissão).
  Future<void> relocate() async {
    ref.invalidate(userLocationProvider);
  }
}

final climateProvider = AsyncNotifierProvider<ClimateController, ClimateData>(ClimateController.new);

/// Contexto completo do usuário para o agente.
final userContextProvider = Provider<UserContext>((ref) {
  final outdoor = ref.watch(outdoorSessionProvider);
  return UserContext(
    persona: ref.watch(personaProvider),
    exposureMinutesToday: outdoor.minutesToday,
    waterMlToday: ref.watch(hydrationProvider).totalMl,
    sensitivityOffset: ref.watch(adaptiveProvider.select((p) => p.sensitivityOffset)),
    isMoving: outdoor.active,
  );
});

/// Avaliação de risco calculada no aparelho (instantânea e offline).
final riskProvider = Provider<RiskAssessment?>((ref) {
  final climate = ref.watch(climateProvider).valueOrNull;
  if (climate == null) return null;
  return const RiskEngine().assess(climate.current, ref.watch(userContextProvider));
});

/// Parcelas que explicam o número (transparência do agente).
final riskBreakdownProvider = Provider<Map<String, double>>((ref) {
  final climate = ref.watch(climateProvider).valueOrNull;
  if (climate == null) return const {};
  return const RiskEngine().breakdown(climate.current, ref.watch(userContextProvider));
});

final comfortWindowsProvider = Provider<({List<ComfortWindow> best, ComfortWindow? avoid})>((ref) {
  final climate = ref.watch(climateProvider).valueOrNull;
  if (climate == null) return (best: const [], avoid: null);
  final now = DateTime.now();
  return (
    best: bestOutdoorWindows(climate.hourly, now: now),
    avoid: worstWindow(climate.hourly, now: now),
  );
});
