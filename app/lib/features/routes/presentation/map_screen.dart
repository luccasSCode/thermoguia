import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/config/app_config.dart';
import '../../../core/providers.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import '../../air/air_providers.dart';
import '../../climate/climate_providers.dart';
import '../../hydration/hydration_controller.dart';
import '../../safety/emergency_sheet.dart';
import '../../session/presentation/session_controller.dart';
import '../data/route_models.dart';
import 'map_effects.dart';
import 'navigation_controller.dart';
import 'route_conditions.dart';
import 'routes_controller.dart';
import 'search_sheet.dart';
import 'trip_controller.dart';
import 'trip_sheets.dart';
import '../../../core/widgets/thermo_loader.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  bool _showOases = true;
  bool _showSmoke = true;

  /// Durante o trajeto, o mapa acompanha a pessoa (como no Waze) até ela
  /// arrastar o mapa; aí aparece o botão "Recentralizar".
  bool _follow = true;

  void _followTo(NavState nav) {
    final p = nav.position;
    if (p == null) return;
    _map.moveAndRotate(LatLng(p.lat, p.lng), 18, -nav.course);
  }

  void _recenter() {
    setState(() => _follow = true);
    final nav = ref.read(navigationProvider);
    if (nav != null) _followTo(nav);
  }

  void _fit(List<LatLng> pts) {
    if (pts.length < 2) return;
    _map.fitCamera(CameraFit.bounds(
      bounds: LatLngBounds.fromPoints(pts),
      padding: const EdgeInsets.fromLTRB(48, 120, 48, 360),
    ));
  }

  Future<void> _pickDestination() async {
    final p = await showSearchSheet(context);
    if (p != null) ref.read(routesProvider.notifier).setDestination(p);
  }

  @override
  Widget build(BuildContext context) {
    final loc = ref.watch(userLocationProvider).valueOrNull;
    final live = ref.watch(liveLocationProvider).valueOrNull;
    final routes = ref.watch(routesProvider);
    final trip = ref.watch(tripProvider);
    final nav = ref.watch(navigationProvider);
    final oases = _showOases ? (ref.watch(oasesProvider).valueOrNull ?? const <Oasis>[]) : const <Oasis>[];
    final reports = ref.watch(reportsProvider).valueOrNull ?? const <CommunityReport>[];
    final smoke = _showSmoke ? (ref.watch(airMapProvider).valueOrNull ?? const <AirMapPoint>[]) : const <AirMapPoint>[];
    final conditions = trip == null ? ref.watch(routeConditionsProvider) : null;
    final mePoint = nav?.position ?? live ?? loc?.point;
    final me =
        mePoint == null ? const LatLng(AppConfig.defaultLat, AppConfig.defaultLng) : LatLng(mePoint.lat, mePoint.lng);

    ref.listen(routesProvider.select((s) => s.selectedRoute), (_, r) {
      if (r != null && ref.read(tripProvider) == null) _fit(r.points);
    });
    ref.listen(navigationProvider, (prev, n) {
      if (n == null) {
        if (prev != null) _map.rotate(0);
        return;
      }
      if (prev == null && !_follow) setState(() => _follow = true);
      if (_follow || prev == null) _followTo(n);
    });

    final shown = trip?.route ?? routes.selectedRoute;
    final others = trip != null
        ? const <RouteOption>[]
        : (routes.result?.routes ?? const <RouteOption>[]).where((r) => r != shown).toList();
    final dest = trip?.destination ?? routes.destination;

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter: me,
              initialZoom: 15,
              minZoom: 11,
              maxZoom: 19,
              onLongPress: (_, p) => showReportSheet(context, ref, GeoPoint(p.latitude, p.longitude)),
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _follow && trip != null) setState(() => _follow = false);
              },
            ),
            children: [
              TileLayer(urlTemplate: AppConfig.tileUrl, userAgentPackageName: AppConfig.packageName),
              // Fumaça por região: manchas na cor da qualidade do ar de cada ponto.
              if (smoke.isNotEmpty)
                CircleLayer(circles: [
                  for (final p in smoke)
                    CircleMarker(
                      point: LatLng(p.lat, p.lng),
                      radius: 3200,
                      useRadiusInMeter: true,
                      color: Tokens.air(p.level).withValues(alpha: p.level.isBad ? 0.22 : 0.12),
                    ),
                ]),
              // Animações: fumaça se mexendo onde o ar está ruim e sol no destino
              // quando o sol está forte.
              MarkerLayer(markers: [
                for (final p in smoke)
                  if (p.level.isBad)
                    Marker(
                      point: LatLng(p.lat, p.lng),
                      width: 160,
                      height: 160,
                      child: SmokeCloud(color: Tokens.air(p.level)),
                    ),
                if (dest != null && conditions != null && conditions.smokeAtDestination)
                  Marker(
                    point: dest.latLng,
                    width: 190,
                    height: 190,
                    child: SmokeCloud(color: Tokens.air(conditions.destinationAir!)),
                  ),
                if (dest != null && conditions?.sun != null)
                  Marker(point: dest.latLng, width: 150, height: 150, child: const SunGlow()),
              ]),
              PolylineLayer(polylines: [
                for (final r in others)
                  Polyline(points: r.points, strokeWidth: 5, color: Colors.grey.withValues(alpha: 0.7)),
                // Brilho verde em volta da rota escolhida.
                if (shown != null)
                  Polyline(points: shown.points, strokeWidth: 20, color: Tokens.copa.withValues(alpha: 0.18)),
                if (shown != null) ..._shadeLines(shown, context.sunMode ? 9 : 7),
              ]),
              MarkerLayer(markers: [
                for (final o in oases)
                  Marker(
                    point: o.latLng,
                    width: 34,
                    height: 34,
                    child: Tooltip(message: o.name, child: _Pin(icon: oasisIcon(o.kind), color: Tokens.rio)),
                  ),
                for (final r in reports)
                  Marker(
                    point: r.latLng,
                    width: 30,
                    height: 30,
                    child: Tooltip(
                      message: r.note.isEmpty ? r.kind.label : '${r.kind.label}: ${r.note}',
                      child: _Pin(
                        icon: reportIcon(r.kind),
                        color: switch (r.kind) {
                          ReportKind.sombraBoa => Tokens.copa,
                          ReportKind.fumaca => const Color(0xFF8E3FAE),
                          _ => Tokens.sol,
                        },
                        small: true,
                      ),
                    ),
                  ),
                if (dest != null)
                  Marker(
                      point: dest.latLng,
                      width: 44,
                      height: 44,
                      child: const _Pin(icon: Icons.flag, color: Tokens.copa)),
                if (nav != null && nav.position != null)
                  Marker(point: me, width: 44, height: 44, child: _NavArrow(course: nav.course))
                else
                  Marker(point: me, width: 26, height: 26, child: const _Me()),
              ]),
              const RichAttributionWidget(attributions: [
                TextSourceAttribution('© OpenStreetMap'),
                TextSourceAttribution('Fumaça: CAMS/Open-Meteo'),
              ]),
            ],
          ),
          if (trip != null && nav != null)
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: _ManeuverBanner(nav: nav, destination: trip.destination.name),
              ),
            )
          else
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Column(children: [
                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          elevation: 3,
                          borderRadius: BorderRadius.circular(Tokens.radiusControl),
                          color: Theme.of(context).colorScheme.surface,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(Tokens.radiusControl),
                            onTap: trip == null ? _pickDestination : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                              child: Row(children: [
                                const Icon(Icons.search),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    dest?.name ?? 'Para onde você vai?',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                ),
                                if (dest != null && trip == null)
                                  GestureDetector(
                                    onTap: () => ref.read(routesProvider.notifier).clear(),
                                    child: const Icon(Icons.close, semanticLabel: 'Limpar destino'),
                                  ),
                              ]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: _showOases ? Icons.water_drop : Icons.water_drop_outlined,
                        tooltip: _showOases ? 'Ocultar pontos de refresco' : 'Mostrar pontos de refresco',
                        onTap: () => setState(() => _showOases = !_showOases),
                      ),
                      const SizedBox(width: 8),
                      _RoundButton(
                        icon: Icons.air,
                        tooltip: _showSmoke ? 'Ocultar fumaça' : 'Mostrar fumaça por região',
                        selected: _showSmoke,
                        onTap: () => setState(() => _showSmoke = !_showSmoke),
                      ),
                      const SizedBox(width: 8),
                      _RoundButton(
                          icon: Icons.my_location, tooltip: 'Minha localização', onTap: () => _map.move(me, 16)),
                    ],
                  ),
                  if (loc != null && loc.isApproximate) _GpsNotice(status: loc.status),
                  if (smoke.any((p) => p.level.isBad)) _SmokeBanner(points: smoke),
                ]),
              ),
            ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (trip != null && !_follow)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 0, 16, 10),
                    child: FloatingActionButton.extended(
                      heroTag: 'recentralizar',
                      onPressed: _recenter,
                      icon: const Icon(Icons.navigation),
                      label: const Text('Recentralizar'),
                    ),
                  ),
                if (trip != null && nav?.alert != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: _AlertCard(alert: nav!.alert!),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.5),
                  child: _Panel(onPickDestination: _pickDestination),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Rota pintada por trechos: verde = sombra, amarelo = meia-sombra, laranja = sol.
  List<Polyline> _shadeLines(RouteOption r, double width) {
    if (r.points.length < 2) return const [];
    final out = <Polyline>[];
    var seg = <LatLng>[r.points.first];
    var color = Tokens.shade(r.shade.first);
    for (var i = 1; i < r.points.length; i++) {
      seg.add(r.points[i]);
      final c = Tokens.shade(r.shade[i]);
      if (c != color) {
        out.add(
            Polyline(points: seg, color: color, strokeWidth: width, borderStrokeWidth: 2, borderColor: Colors.white));
        seg = [r.points[i]];
        color = c;
      }
    }
    if (seg.length > 1) {
      out.add(Polyline(points: seg, color: color, strokeWidth: width, borderStrokeWidth: 2, borderColor: Colors.white));
    }
    return out;
  }
}

class _Panel extends ConsumerWidget {
  const _Panel({required this.onPickDestination});
  final VoidCallback onPickDestination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final trip = ref.watch(tripProvider);
    final s = ref.watch(routesProvider);
    final child = trip != null
        ? _TripPanel(trip: trip)
        : s.destination == null
            ? _IdlePanel(onPickDestination: onPickDestination)
            : _RoutesPanel(state: s);
    // Com destino escolhido, "Iniciar trajeto" fica fixo embaixo, sempre à vista.
    final route = s.selectedRoute;
    final start = trip == null && s.destination != null && s.error == null
        ? FilledButton.icon(
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Iniciar trajeto'),
            onPressed: s.loading || route == null
                ? null
                : () => ref.read(tripProvider.notifier).start(route, s.result!.routes),
          )
        : null;
    return Material(
      elevation: 8,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
        side: context.sunMode ? const BorderSide(color: Colors.black, width: 2) : BorderSide.none,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(20, 18, 20, start == null ? 16 : 10),
                child: child,
              ),
            ),
            if (start != null) Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 12), child: start),
          ],
        ),
      ),
    );
  }
}

class _IdlePanel extends ConsumerWidget {
  const _IdlePanel({required this.onPickDestination});
  final VoidCallback onPickDestination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.read(routesRepositoryProvider).savedPlaces;
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rotas Frescas', style: t.titleLarge),
        const SizedBox(height: 6),
        Text('Escolha um destino e comparamos os caminhos pela sombra no horário em que você vai passar. '
            'As manchas mostram a fumaça por região.',
            style: t.bodyMedium),
        if (saved.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in saved)
              ActionChip(
                avatar: Icon(p.savedAs == 'Casa' ? Icons.home_outlined : Icons.bookmark_outline, size: 18),
                label: Text(p.savedAs!),
                onPressed: () => ref.read(routesProvider.notifier).setDestination(p),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        Text('Toque e segure no mapa para marcar sombra, trecho sem sombra ou água.', style: t.bodySmall),
      ],
    );
  }
}

class _RoutesPanel extends ConsumerWidget {
  const _RoutesPanel({required this.state});
  final RoutesState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctrl = ref.read(routesProvider.notifier);
    final t = Theme.of(context).textTheme;
    final result = state.result;
    final conditions = ref.watch(routeConditionsProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: SegmentedButton<String>(
              segments: [
                for (final m in travelModesFor(ref.watch(personaProvider)))
                  switch (m) {
                    'moto' => const ButtonSegment(value: 'moto', icon: Icon(Icons.two_wheeler), label: Text('Moto')),
                    'bike' => const ButtonSegment(
                        value: 'bike', icon: Icon(Icons.directions_bike), label: Text('Bicicleta')),
                    _ => const ButtonSegment(value: 'foot', icon: Icon(Icons.directions_walk), label: Text('A pé')),
                  },
              ],
              selected: {state.mode},
              onSelectionChanged: (v) => ctrl.setMode(v.first),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (min, label) in const [(0, 'Agora'), (30, 'Em 30 min'), (60, 'Em 1 h'), (120, 'Em 2 h')])
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(label),
                  selected: state.departInMin == min,
                  onSelected: (_) => ctrl.setDeparture(min),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 12),
        if (state.loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: ThermoLoader(size: 88, message: 'Procurando o caminho mais fresco…')),
          )
        else if (state.error != null)
          ErrorView(error: state.error!, onRetry: ctrl.compute)
        else if (result != null) ...[
          if (conditions != null && conditions.any)
            ConditionsWarning(conditions: conditions, destination: state.destination!),
          Text(result.advice, style: t.bodyLarge),
          if (result.routes.any((r) => r.approximate))
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Não há caminho ${state.mode == 'bike' ? 'de bicicleta' : 'a pé'} mapeado até aqui, então '
                    'seguimos pelas ruas da cidade. Parte do trajeto pode não ter '
                    '${state.mode == 'bike' ? 'ciclovia' : 'calçada'}: atenção ao trânsito.',
                    style: t.bodySmall,
                  ),
                ),
              ]),
            ),
          if (!result.greenReady)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                  'O mapa de árvores ainda está carregando no servidor; a sombra foi estimada pela posição do sol.',
                  style: t.bodySmall),
            ),
          const SizedBox(height: 12),
          for (var i = 0; i < result.routes.length; i++)
            _RouteTile(
              route: result.routes[i],
              selected: i == state.selected,
              onTap: () => ctrl.select(i),
            ),
          const _Legend(),
        ],
      ],
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({required this.route, required this.selected, required this.onTap});
  final RouteOption route;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final shade = (route.shadeScore * 100).round();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Tokens.radiusControl),
            border: Border.all(
              color: selected ? (route.recommended ? Tokens.copa : scheme.primary) : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                if (route.recommended) const Icon(Icons.park, color: Tokens.copa, size: 20),
                if (route.recommended) const SizedBox(width: 6),
                Expanded(child: Text(route.label, style: t.titleMedium)),
                Text(formatDuration(route.durationS), style: t.titleMedium),
              ]),
              if (route.tags.length > 1) Text(route.tags.skip(1).join(' e '), style: t.bodySmall),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: route.shadeScore,
                  minHeight: 6,
                  color: Tokens.copa,
                  backgroundColor: Tokens.sol.withValues(alpha: 0.35),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '$shade% com sombra, ${route.sunExposureMin.round()} min ao sol, ${formatDistance(route.distanceM)}',
                style: t.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    Widget dot(Color c, String l) => Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 14, height: 6, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
          const SizedBox(width: 6),
          Text(l, style: Theme.of(context).textTheme.bodySmall),
        ]);
    return Wrap(spacing: 16, children: [
      dot(Tokens.copa, 'Sombra'),
      dot(const Color(0xFFC79A1E), 'Meia-sombra'),
      dot(Tokens.sol, 'Sol direto'),
    ]);
  }
}

class _TripPanel extends ConsumerWidget {
  const _TripPanel({required this.trip});
  final ActiveTrip trip;

  Future<void> _finish(BuildContext context, WidgetRef ref) async {
    final f = await showComfortFeedback(context);
    await ref.read(tripProvider.notifier).finish(f);
    if (context.mounted && f != null) showMessage(context, 'Obrigado! Suas próximas rotas vão considerar isso.');
  }

  /// Abre o trajeto no app de mapas do aparelho (Apple Mapas no iPhone,
  /// Google Maps no Android). O caminho pode não ser a Rota Fresca.
  Future<void> _openExternal(BuildContext context) async {
    final d = trip.destination;
    final (apple, google) = switch (trip.mode) {
      'moto' => ('d', 'two-wheeler'),
      'bike' => ('c', 'bicycling'),
      _ => ('w', 'walking'),
    };
    final uri = defaultTargetPlatform == TargetPlatform.iOS
        ? Uri.parse('https://maps.apple.com/?daddr=${d.lat},${d.lng}&dirflg=$apple')
        : Uri.parse('https://www.google.com/maps/dir/?api=1&destination=${d.lat},${d.lng}'
            '&travelmode=$google');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && context.mounted) {
      showMessage(context, 'Não foi possível abrir o app de mapas.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final nav = ref.watch(navigationProvider);
    final risk = ref.watch(riskProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final remaining = nav?.remaining ?? Duration(seconds: trip.route.durationS.round());
    final eta = DateTime.now().add(remaining);
    final meters = nav?.remainingM ?? trip.route.distanceM;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(hm(eta), style: t.headlineMedium?.copyWith(color: Tokens.copa, fontWeight: FontWeight.w700)),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('${formatDuration(remaining.inSeconds.toDouble())} · ${formatDistance(meters)}',
                    style: t.titleMedium),
              ),
            ),
            IconButton.filledTonal(
              tooltip: (nav?.muted ?? false) ? 'Ligar a voz' : 'Silenciar a voz',
              icon: Icon((nav?.muted ?? false) ? Icons.volume_off : Icons.volume_up),
              onPressed: () => ref.read(navigationProvider.notifier).toggleMute(),
            ),
          ],
        ),
        Text('Para ${trip.destination.name} · ${(trip.route.shadeScore * 100).round()}% com sombra',
            style: t.bodyMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (risk?.level == RiskLevel.extremo) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Tokens.risk(RiskLevel.extremo).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
            ),
            child: Text(
              'Calor extremo. Faça uma pausa em um ponto de refresco (gotas azuis no mapa).',
              style: t.bodyLarge?.copyWith(color: Tokens.risk(RiskLevel.extremo, sunMode: context.sunMode)),
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(children: [
          _TripAction(
            icon: Icons.add_alert_outlined,
            label: 'Relatar',
            onTap: () {
              final p = nav?.position ?? ref.read(userLocationProvider).valueOrNull?.point;
              if (p != null) showReportSheet(context, ref, p);
            },
          ),
          _TripAction(
            icon: Icons.water_drop_outlined,
            label: 'Bebi água',
            onTap: () {
              ref.read(hydrationProvider.notifier).add(200);
              showMessage(context, '+200 ml registrados.');
            },
          ),
          _TripAction(
            icon: Icons.emergency_outlined,
            label: 'Passando mal',
            color: scheme.error,
            onTap: () => showEmergencySheet(context, trigger: 'trajeto'),
          ),
          _TripAction(icon: Icons.open_in_new, label: 'Abrir no Mapas', onTap: () => _openExternal(context)),
        ]),
        const SizedBox(height: 10),
        if (nav?.arrived ?? false)
          FilledButton.icon(
            icon: const Icon(Icons.flag),
            onPressed: () => _finish(context, ref),
            label: const Text('Cheguei'),
          )
        else
          OutlinedButton(onPressed: () => _finish(context, ref), child: const Text('Encerrar trajeto')),
      ],
    );
  }
}

class _TripAction extends StatelessWidget {
  const _TripAction({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.onSurface;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            Icon(icon, color: c),
            const SizedBox(height: 4),
            Text(label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c)),
          ]),
        ),
      ),
    );
  }
}

/// Faixa do topo: a próxima manobra, grande, como nos apps de navegação.
class _ManeuverBanner extends StatelessWidget {
  const _ManeuverBanner({required this.nav, required this.destination});
  final NavState nav;
  final String destination;

  @override
  Widget build(BuildContext context) {
    final sun = context.sunMode;
    final bg = sun ? Colors.black : Tokens.rioProfundo;
    final t = Theme.of(context).textTheme;
    const fg = Colors.white;

    final (IconData icon, String big, String text) = switch (nav) {
      NavState(gpsOk: false) => (Icons.location_disabled, 'Sem GPS', 'Ative a localização para receber as instruções.'),
      NavState(rerouting: true) => (
          Icons.alt_route,
          'Recalculando',
          'Procurando o caminho mais fresco a partir daqui…'
        ),
      NavState(arrived: true) => (Icons.flag, 'Você chegou', destination),
      NavState(position: null) => (
          Icons.gps_not_fixed,
          'Buscando GPS',
          nav.route.maneuvers.isEmpty ? 'Siga a linha no mapa.' : nav.route.maneuvers.first.instruction
        ),
      NavState(next: final m?) => (maneuverIcon(m), formatDistance(_round(nav.distToNext)), m.instruction),
      _ => (Icons.straight, '', 'Siga a linha no mapa.'),
    };
    final after = nav.after;
    final showAfter =
        !nav.arrived && !nav.rerouting && nav.next != null && after != null && after.along - nav.next!.along < 150;

    return Semantics(
      liveRegion: true,
      label: big.isEmpty ? text : '$big. $text',
      child: ExcludeSemantics(
        child: Material(
          color: bg,
          elevation: 6,
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          clipBehavior: Clip.antiAlias,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
                nav.rerouting
                    ? const SizedBox(width: 52, height: 52, child: Center(child: ThermoLoader.inline(size: 30)))
                    : Icon(icon, size: 52, color: fg),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (big.isNotEmpty)
                      Text(big, style: t.headlineSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
                    Text(text,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: t.titleMedium?.copyWith(color: fg.withValues(alpha: 0.92))),
                  ]),
                ),
              ]),
            ),
            if (showAfter)
              Container(
                width: double.infinity,
                color: Colors.black.withValues(alpha: 0.25),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(children: [
                  Text('Depois', style: t.labelLarge?.copyWith(color: fg)),
                  const SizedBox(width: 8),
                  Icon(maneuverIcon(after), size: 20, color: fg),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(after.instruction,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: fg)),
                  ),
                ]),
              ),
          ]),
        ),
      ),
    );
  }

  static double _round(double m) => m < 100 ? (m / 5).round() * 5.0 : (m / 10).round() * 10.0;
}

IconData maneuverIcon(Maneuver m) {
  final mod = m.modifier;
  return switch (m.type) {
    'arrive' => Icons.flag,
    'depart' => Icons.navigation,
    'roundabout' ||
    'rotary' ||
    'roundabout turn' ||
    'exit roundabout' ||
    'exit rotary' =>
      mod.contains('left') ? Icons.roundabout_left : Icons.roundabout_right,
    'fork' => mod.contains('left') ? Icons.fork_left : Icons.fork_right,
    'merge' => Icons.merge,
    _ => switch (mod) {
        'left' => Icons.turn_left,
        'right' => Icons.turn_right,
        'slight left' => Icons.turn_slight_left,
        'slight right' => Icons.turn_slight_right,
        'sharp left' => Icons.turn_sharp_left,
        'sharp right' => Icons.turn_sharp_right,
        'uturn' => Icons.u_turn_left,
        _ => Icons.straight,
      },
  };
}

/// Aviso do caminho: sol forte, lado da sombra, ponto de água, relatos.
class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert});
  final RouteAlert alert;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color color, String title) = switch (alert.kind) {
      'sol_forte' => (Icons.wb_sunny, Tokens.sol, 'Sol forte'),
      'lado_sombra' => (Icons.park, Tokens.copa, 'Lado da sombra'),
      'sombra' || 'sombra_boa' => (Icons.park, Tokens.copa, 'Sombra'),
      'refresco' || 'bebedouro' => (Icons.water_drop, Tokens.rio, 'Ponto de refresco'),
      'transito' => (Icons.traffic, Tokens.risk(RiskLevel.muitoAlto), 'Trânsito'),
      'obra' => (Icons.construction, Tokens.risk(RiskLevel.moderado), 'Obra'),
      'alagamento' => (Icons.flood, Tokens.rio, 'Alagamento'),
      _ => (Icons.local_fire_department, Tokens.risk(RiskLevel.muitoAlto), 'Calor'),
    };
    final t = Theme.of(context).textTheme;
    final side = alert.side;
    return Material(
      elevation: 4,
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(Tokens.radiusBlock),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          border: Border(left: BorderSide(color: color, width: 6)),
        ),
        child: Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: t.labelLarge?.copyWith(color: color)),
              Text(alert.message, style: t.bodyMedium),
            ]),
          ),
          if (side != null) ...[
            const SizedBox(width: 8),
            Icon(side == Side.direito ? Icons.arrow_forward : Icons.arrow_back,
                color: color, size: 30, semanticLabel: 'lado ${side.label}'),
          ],
        ]),
      ),
    );
  }
}

/// Seta da posição durante a navegação, apontando para onde a pessoa vai.
class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.course});
  final double course;

  @override
  Widget build(BuildContext context) => Transform.rotate(
        angle: course * math.pi / 180,
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(blurRadius: 6, color: Colors.black38)],
          ),
          child: const Icon(Icons.navigation, color: Tokens.rio, size: 32),
        ),
      );
}

/// Aviso de GPS desligado na tela do mapa, com o atalho para ligar.
class _GpsNotice extends ConsumerWidget {
  const _GpsNotice({required this.status});
  final LocationStatus status;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Material(
          elevation: 2,
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 4, 4),
            child: Row(children: [
              const Icon(Icons.location_off_outlined, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text('Sem GPS: a navegação precisa da sua localização.',
                    style: Theme.of(context).textTheme.bodyMedium),
              ),
              TextButton(
                onPressed: () async {
                  final svc = ref.read(locationServiceProvider);
                  final now = await svc.ensurePermission();
                  if (now != LocationStatus.ok) await svc.openSettings();
                  ref.read(climateProvider.notifier).relocate();
                },
                child: const Text('Ativar'),
              ),
            ]),
          ),
        ),
      );
}

class _Pin extends StatelessWidget {
  const _Pin({required this.icon, required this.color, this.small = false});
  final IconData icon;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2),
          boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black26)],
        ),
        child: Icon(icon, color: color, size: small ? 16 : 20),
      );
}

class _Me extends StatelessWidget {
  const _Me();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Tokens.rio,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 4),
          boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
        ),
      );
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.selected = false});
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
        elevation: 3,
        shape: const CircleBorder(),
        color: selected ? Tokens.copa : Theme.of(context).colorScheme.surface,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: selected ? Colors.white : null),
          onPressed: onTap,
        ),
      );
}

/// Onde a fumaça está pior agora, em palavras ("zona Norte, índice 190").
class _SmokeBanner extends StatelessWidget {
  const _SmokeBanner({required this.points});
  final List<AirMapPoint> points;

  @override
  Widget build(BuildContext context) {
    final worst = points.reduce((a, b) => a.index >= b.index ? a : b);
    final t = Theme.of(context).textTheme;
    final color = Tokens.air(worst.level, sunMode: context.sunMode);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        elevation: 2,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Icon(Icons.air, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Fumaça pior ${zoneOf(worst.lat, worst.lng)}: ar ${worst.level.label.toLowerCase()} '
                '(índice ${worst.index}). Toque e segure no mapa para relatar fumaça.',
                style: t.bodySmall,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
