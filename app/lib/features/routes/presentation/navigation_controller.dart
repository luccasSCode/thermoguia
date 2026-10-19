import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/providers.dart';
import '../../../core/services/location_service.dart';
import '../../../core/services/voice_guide.dart';
import '../../adaptive/adaptive_controller.dart';
import '../data/route_models.dart';
import 'routes_controller.dart';
import 'trip_controller.dart';

/// Estado da navegação curva a curva.
class NavState {
  const NavState({
    required this.route,
    this.position,
    this.course = 0,
    this.fix,
    this.next,
    this.after,
    this.distToNext = 0,
    this.remainingM = 0,
    this.alert,
    this.gpsOk = true,
    this.offRoute = false,
    this.rerouting = false,
    this.arrived = false,
    this.muted = false,
  });

  final RouteOption route;
  final GeoPoint? position;

  /// Rumo de deslocamento, em graus (0 = norte). Gira o mapa.
  final double course;
  final RouteFix? fix;

  /// Próxima manobra e a seguinte (para o "Depois, ...").
  final Maneuver? next;
  final Maneuver? after;
  final double distToNext;
  final double remainingM;

  /// Aviso visível agora (sol forte, lado da sombra, relato...).
  final RouteAlert? alert;
  final bool gpsOk;
  final bool offRoute;
  final bool rerouting;
  final bool arrived;
  final bool muted;

  /// Tempo restante, na velocidade prevista pela rota.
  Duration get remaining => route.distanceM <= 0
      ? Duration.zero
      : Duration(seconds: (remainingM * route.durationS / route.distanceM).round());

  NavState copyWith({
    RouteOption? route,
    GeoPoint? position,
    double? course,
    RouteFix? fix,
    Maneuver? next,
    bool clearNext = false,
    Maneuver? after,
    bool clearAfter = false,
    double? distToNext,
    double? remainingM,
    RouteAlert? alert,
    bool clearAlert = false,
    bool? gpsOk,
    bool? offRoute,
    bool? rerouting,
    bool? arrived,
    bool? muted,
  }) =>
      NavState(
        route: route ?? this.route,
        position: position ?? this.position,
        course: course ?? this.course,
        fix: fix ?? this.fix,
        next: clearNext ? null : (next ?? this.next),
        after: clearAfter ? null : (after ?? this.after),
        distToNext: distToNext ?? this.distToNext,
        remainingM: remainingM ?? this.remainingM,
        alert: clearAlert ? null : (alert ?? this.alert),
        gpsOk: gpsOk ?? this.gpsOk,
        offRoute: offRoute ?? this.offRoute,
        rerouting: rerouting ?? this.rerouting,
        arrived: arrived ?? this.arrived,
        muted: muted ?? this.muted,
      );
}

/// Segue o GPS durante o trajeto: projeta a posição na rota, anuncia as
/// manobras e os avisos (por voz e na tela) e recalcula se a pessoa sair
/// do caminho.
class NavigationController extends Notifier<NavState?> {
  StreamSubscription<Position>? _sub;
  late VoiceGuide _voice;
  late RouteLine _line;
  int _hint = 0;
  int _offCount = 0;
  DateTime _lastReroute = DateTime.fromMillisecondsSinceEpoch(0);
  final _spoken = <String>{};

  String get _mode => ref.read(tripProvider)?.mode ?? 'foot';

  // Distâncias de aviso: a pé se anda ~1,3 m/s; de bicicleta, ~4 m/s; de moto, ~9 m/s.
  double get _farM => switch (_mode) { 'moto' => 300, 'bike' => 160, _ => 60 };
  double get _nearM => switch (_mode) { 'moto' => 60, 'bike' => 35, _ => 15 };
  double get _alertAheadM => switch (_mode) { 'moto' => 220, 'bike' => 110, _ => 40 };
  double get _offRouteM => switch (_mode) { 'moto' => 50, 'bike' => 45, _ => 35 };

  @override
  NavState? build() {
    // Guardado aqui: no descarte do provider o ref já não pode ser usado.
    _voice = ref.read(voiceGuideProvider);
    ref.onDispose(_teardown);
    return null;
  }

  Future<void> start(RouteOption route) async {
    _teardown();
    _useRoute(route);
    final muted = ref.read(localStoreProvider).getString('nav_muted') == '1';
    final first = route.maneuvers.isEmpty ? null : route.maneuvers.first;
    state = NavState(
      route: route,
      next: route.maneuvers.length > 1 ? route.maneuvers[1] : null,
      distToNext: route.maneuvers.length > 1 ? route.maneuvers[1].along : 0,
      remainingM: _line.length,
      course: route.points.length > 1 ? bearingDeg(route.points[0].geo, route.points[1].geo) : 0,
      muted: muted,
    );
    unawaited(WakelockPlus.enable().catchError((_) {}));

    final status = await ref.read(locationServiceProvider).ensurePermission();
    if (state == null) return;
    if (status != LocationStatus.ok) {
      state = state!.copyWith(gpsOk: false);
      _say('Não consigo acessar sua localização. Ative o GPS para receber as instruções.');
      return;
    }
    final next = state!.next;
    final soon = next != null && state!.distToNext <= _nearM;
    if (next != null) {
      _spoken.add('m1-antes');
      if (soon) _spoken.add('m1-agora');
    }
    _say([
      'Vamos lá.',
      if (first != null) '${first.instruction}.',
      if (next != null)
        soon ? 'Depois, ${_lower(next.instruction)}.' : '${spokenDistance(state!.distToNext)}, ${_lower(next.instruction)}.',
    ].join(' '));
    _sub = Geolocator.getPositionStream(locationSettings: _settings()).listen(
      _onPosition,
      onError: (_) => state = state?.copyWith(gpsOk: false),
    );
  }

  void stop() {
    _teardown();
    state = null;
  }

  Future<void> toggleMute() async {
    final s = state;
    if (s == null) return;
    state = s.copyWith(muted: !s.muted);
    if (!s.muted) await _voice.stop();
    await ref.read(localStoreProvider).setString('nav_muted', s.muted ? '0' : '1');
  }

  LocationSettings _settings() => switch (defaultTargetPlatform) {
        TargetPlatform.iOS => AppleSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            activityType: ActivityType.fitness,
            distanceFilter: 2,
            pauseLocationUpdatesAutomatically: false,
          ),
        TargetPlatform.android => AndroidSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 2,
            intervalDuration: const Duration(seconds: 1),
          ),
        _ => const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 2),
      };

  void _useRoute(RouteOption route) {
    _line = RouteLine([for (final p in route.points) p.geo]);
    _hint = 0;
    _offCount = 0;
    _spoken.clear();
  }

  void _onPosition(Position pos) {
    final s = state;
    if (s == null || s.rerouting) return;
    final here = GeoPoint(pos.latitude, pos.longitude);
    final fix = _line.project(here, hint: _hint, window: 60);
    _hint = fix.segment;

    // Fora da rota? Só confiamos em leituras precisas, e em sequência.
    if (fix.offset > _offRouteM && pos.accuracy < 40) {
      _offCount++;
    } else {
      _offCount = 0;
    }
    final offRoute = _offCount >= 3;

    final course = pos.speed > 0.6 && pos.heading >= 0 ? pos.heading : _line.at(fix.along).$2;
    final ms = s.route.maneuvers;
    final i = ms.indexWhere((m) => m.along > fix.along + 3, 1);
    final next = i < 0 ? null : ms[i];
    final after = (i < 0 || i + 1 >= ms.length) ? null : ms[i + 1];
    final dist = next == null ? 0.0 : next.along - fix.along;
    final remaining = (_line.length - fix.along).clamp(0.0, double.infinity);
    final arrived = remaining < 20 || (next?.isArrival == true && dist < 15 && fix.offset < 40);

    final alert = s.route.alerts.where((a) {
      final from = a.along - _alertAheadM;
      final to = a.along + (a.length > 0 ? a.length : 40);
      return fix.along >= from && fix.along <= to;
    }).firstOrNull;

    state = s.copyWith(
      position: here,
      course: course,
      fix: fix,
      next: next,
      clearNext: next == null,
      after: after,
      clearAfter: after == null,
      distToNext: dist,
      remainingM: remaining,
      alert: alert,
      clearAlert: alert == null,
      gpsOk: true,
      offRoute: offRoute,
      arrived: arrived,
    );

    if (arrived) {
      _once('chegada', 'Você chegou ao destino. Não esqueça de beber água.');
      return;
    }
    if (offRoute) {
      unawaited(_reroute(here));
      return;
    }
    if (next != null && i >= 0) {
      if (dist <= _nearM) {
        _once('m$i-agora', next.isArrival ? 'Seu destino está logo à frente.' : '${next.instruction}.');
      } else if (dist <= _farM) {
        _once('m$i-antes', '${spokenDistance(dist)}, ${_lower(next.instruction)}.');
      }
    }
    if (alert != null) {
      final prefix = alert.kind == 'refresco' || alert.kind == 'sombra' || alert.kind == 'lado_sombra' ? '' : 'Atenção: ';
      _once('a${alert.along.round()}-${alert.kind}', '$prefix${alert.message}');
    }
  }

  Future<void> _reroute(GeoPoint from) async {
    final trip = ref.read(tripProvider);
    final s = state;
    if (trip == null || s == null) return;
    if (DateTime.now().difference(_lastReroute) < const Duration(seconds: 15)) return;
    _lastReroute = DateTime.now();
    state = s.copyWith(rerouting: true);
    _say('Você saiu da rota. Recalculando.');
    try {
      final result = await ref.read(routesRepositoryProvider).freshRoutes(
            origin: from,
            destination: trip.destination.geo,
            mode: trip.mode,
            departAt: DateTime.now(),
            shadePreference: ref.read(adaptiveProvider).shadePreference,
          );
      if (state == null || result.routes.isEmpty) return;
      final route = result.routes.first;
      ref.read(tripProvider.notifier).replaceRoute(route);
      _useRoute(route);
      final next = route.maneuvers.length > 1 ? route.maneuvers[1] : null;
      state = state!.copyWith(
        route: route,
        rerouting: false,
        offRoute: false,
        next: next,
        clearNext: next == null,
        distToNext: next?.along ?? 0,
        remainingM: _line.length,
        clearAlert: true,
      );
      _say('Nova rota. ${route.maneuvers.isEmpty ? '' : '${route.maneuvers.first.instruction}.'}');
    } catch (_) {
      state = state?.copyWith(rerouting: false);
    }
  }

  void _once(String key, String text) {
    if (_spoken.add(key)) _say(text);
  }

  void _say(String text) {
    if (state?.muted ?? true) return;
    unawaited(_voice.say(text));
  }

  String _lower(String s) => s.isEmpty ? s : s[0].toLowerCase() + s.substring(1);

  void _teardown() {
    _sub?.cancel();
    _sub = null;
    unawaited(WakelockPlus.disable().catchError((_) {}));
    unawaited(_voice.stop());
  }
}

final navigationProvider = NotifierProvider<NavigationController, NavState?>(NavigationController.new);

extension on LatLng {
  GeoPoint get geo => GeoPoint(latitude, longitude);
}
