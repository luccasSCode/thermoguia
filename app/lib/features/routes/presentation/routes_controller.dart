import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/providers.dart';
import '../../adaptive/adaptive_controller.dart';
import '../../climate/climate_providers.dart';
import '../../session/presentation/session_controller.dart';
import '../data/route_models.dart';
import '../data/routes_repository.dart';

final routesRepositoryProvider = Provider(
  (ref) => RoutesRepository(ref.watch(apiClientProvider), ref.watch(localStoreProvider)),
);

class RoutesState {
  const RoutesState({
    this.destination,
    this.mode = 'foot',
    this.departInMin = 0,
    this.result,
    this.loading = false,
    this.error,
    this.selected = 0,
  });

  final Place? destination;
  final String mode;
  final int departInMin;
  final RoutesResult? result;
  final bool loading;
  final String? error;
  final int selected;

  RouteOption? get selectedRoute =>
      (result == null || result!.routes.isEmpty) ? null : result!.routes[selected.clamp(0, result!.routes.length - 1)];

  RoutesState copyWith({
    Place? destination,
    String? mode,
    int? departInMin,
    RoutesResult? result,
    bool clearResult = false,
    bool? loading,
    String? error,
    bool clearError = false,
    int? selected,
  }) =>
      RoutesState(
        destination: destination ?? this.destination,
        mode: mode ?? this.mode,
        departInMin: departInMin ?? this.departInMin,
        result: clearResult ? null : (result ?? this.result),
        loading: loading ?? this.loading,
        error: clearError ? null : (error ?? this.error),
        selected: selected ?? this.selected,
      );
}

class RoutesController extends Notifier<RoutesState> {
  @override
  RoutesState build() {
    final persona = ref.read(personaProvider);
    return RoutesState(mode: persona == Persona.ciclista ? 'bike' : 'foot');
  }

  void setDestination(Place p) {
    state = state.copyWith(destination: p, clearResult: true, clearError: true, selected: 0);
    compute();
  }

  void setMode(String mode) {
    if (mode == state.mode) return;
    state = state.copyWith(mode: mode);
    compute();
  }

  void setDeparture(int minutes) {
    if (minutes == state.departInMin) return;
    state = state.copyWith(departInMin: minutes);
    compute();
  }

  void select(int i) => state = state.copyWith(selected: i);

  void clear() => state = RoutesState(mode: state.mode);

  Future<void> compute() async {
    final dest = state.destination;
    if (dest == null) return;
    state = state.copyWith(loading: true, clearError: true);
    try {
      final origin = (await ref.read(userLocationProvider.future)).point;
      final result = await ref.read(routesRepositoryProvider).freshRoutes(
            origin: origin,
            destination: dest.geo,
            mode: state.mode,
            departAt: DateTime.now().add(Duration(minutes: state.departInMin)),
            shadePreference: ref.read(adaptiveProvider).shadePreference,
          );
      state = state.copyWith(result: result, loading: false, selected: 0);
    } catch (e) {
      state = state.copyWith(loading: false, error: e.toString(), clearResult: true);
    }
  }
}

final routesProvider = NotifierProvider<RoutesController, RoutesState>(RoutesController.new);

/// Pontos de refresco perto do usuário.
final oasesProvider = FutureProvider.autoDispose<List<Oasis>>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  return ref.read(routesRepositoryProvider).oases(loc.point);
});

final reportsProvider = FutureProvider.autoDispose<List<CommunityReport>>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  return ref.read(routesRepositoryProvider).reports(loc.point);
});
