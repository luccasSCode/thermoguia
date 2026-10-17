import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/providers.dart';
import '../../adaptive/adaptive_controller.dart';
import '../../climate/climate_providers.dart';
import '../../outdoor/outdoor_session_controller.dart';
import '../../rewards/rewards_controller.dart';
import '../data/route_models.dart';
import 'navigation_controller.dart';
import 'routes_controller.dart';

class ActiveTrip {
  const ActiveTrip({
    required this.route,
    required this.destination,
    required this.mode,
    required this.startedAt,
    required this.predictedRisk,
    required this.origin,
  });

  final RouteOption route;
  final Place destination;
  final String mode;
  final DateTime startedAt;
  final RiskLevel predictedRisk;
  final GeoPoint origin;
}

/// Trajeto em andamento. Ao iniciar, o agente aprende com a rota
/// escolhida; ao terminar, com o feedback de conforto.
class TripController extends Notifier<ActiveTrip?> {
  @override
  ActiveTrip? build() => null;

  Future<void> start(RouteOption route, List<RouteOption> all) async {
    final dest = ref.read(routesProvider).destination;
    if (dest == null) return;
    final origin = (await ref.read(userLocationProvider.future)).point;
    final risk = ref.read(riskProvider)?.level ?? RiskLevel.moderado;

    final fastest = all.reduce((a, b) => a.durationS <= b.durationS ? a : b);
    final adaptive = ref.read(adaptiveProvider.notifier);
    await adaptive.recordRouteChoice(
      chosenShade: route.shadeScore,
      fastestShade: fastest.shadeScore,
      durationRatio: route.durationS / fastest.durationS,
    );
    await adaptive.recordDeparture(DateTime.now());

    state = ActiveTrip(
      route: route,
      destination: dest,
      mode: ref.read(routesProvider).mode,
      startedAt: DateTime.now(),
      predictedRisk: risk,
      origin: origin,
    );
    ref.read(outdoorSessionProvider.notifier).start(fromTrip: true);
    unawaited(ref.read(navigationProvider.notifier).start(route));
    await ref.read(auditLoggerProvider).log('trajeto_iniciado', details: {
      'rota': route.label,
      'sombra': (route.shadeScore * 100).round(),
      'risco': risk.name,
    });
  }

  /// Troca a rota em andamento (recálculo quando a pessoa sai do caminho).
  void replaceRoute(RouteOption route) {
    final t = state;
    if (t == null) return;
    state = ActiveTrip(
      route: route,
      destination: t.destination,
      mode: t.mode,
      startedAt: t.startedAt,
      predictedRisk: t.predictedRisk,
      origin: t.origin,
    );
  }

  /// Encerra e registra o feedback (pode ser nulo se o usuário pular).
  Future<void> finish(ComfortFeedback? feedback) async {
    final trip = state;
    if (trip == null) return;
    state = null;
    ref.read(navigationProvider.notifier).stop();
    final outdoor = ref.read(outdoorSessionProvider);
    if (outdoor.fromTrip) ref.read(outdoorSessionProvider.notifier).stop();

    if (feedback != null) {
      await ref.read(adaptiveProvider.notifier).recordComfort(feedback, trip.predictedRisk);
    }
    final end = DateTime.now();
    try {
      final res = await ref.read(routesRepositoryProvider).saveTrip({
        'mode': trip.mode,
        'routeLabel': trip.route.label,
        'origin': trip.origin.toJson(),
        'destination': trip.destination.geo.toJson(),
        'distanceM': trip.route.distanceM,
        'durationS': end.difference(trip.startedAt).inSeconds.toDouble(),
        'shadeScore': trip.route.shadeScore,
        'exposureMin': trip.route.sunExposureMin,
        'riskLevel': trip.predictedRisk.name,
        'feedback': feedback?.name,
        'startedAt': trip.startedAt.toUtc().toIso8601String(),
        'endedAt': end.toUtc().toIso8601String(),
      });
      ref.read(rewardsProvider.notifier).announceFrom(res);
    } catch (_) {}
    ref.read(routesProvider.notifier).clear();
  }
}

final tripProvider = NotifierProvider<TripController, ActiveTrip?>(TripController.new);
