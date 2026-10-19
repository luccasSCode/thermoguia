import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/tokens.dart';
import '../../air/air_providers.dart';
import '../../session/presentation/session_controller.dart';
import '../data/route_models.dart';
import 'routes_controller.dart';

/// Raio de cada mancha de fumaça do mapa (o mesmo desenhado na tela).
const smokeRadiusM = 3200.0;

/// Sol forte: o mesmo critério do aviso de UV do motor de risco.
bool isStrongSun(ClimateSnapshot c) => c.isDay && c.uvIndex >= 8;

/// Manchas de fumaça ruim (ou pior) que o caminho atravessa.
List<AirMapPoint> smokeAlong(List<LatLng> route, List<AirMapPoint> map) {
  const d = Distance();
  return [
    for (final p in map)
      if (p.level.isBad && route.any((q) => d.as(LengthUnit.Meter, q, LatLng(p.lat, p.lng)) <= smokeRadiusM)) p,
  ];
}

/// O que merece aviso no destino e no caminho escolhidos.
class RouteConditions {
  const RouteConditions({this.destinationAir, this.smokeOnRoute = const [], this.sun});

  /// Ar agora no destino, quando já carregou.
  final AirLevel? destinationAir;
  final List<AirMapPoint> smokeOnRoute;

  /// Clima na saída, quando o sol está forte.
  final ClimateSnapshot? sun;

  bool get smokeAtDestination => destinationAir?.isBad ?? false;
  bool get any => smokeAtDestination || smokeOnRoute.isNotEmpty || sun != null;

  /// Pior nível de ar entre o destino e o caminho.
  AirLevel? get worstAir {
    final levels = [if (destinationAir != null) destinationAir!, for (final p in smokeOnRoute) p.level];
    if (levels.isEmpty) return null;
    return levels.reduce((a, b) => a.index >= b.index ? a : b);
  }
}

/// Ar agora num ponto (lat, lng).
final airAtProvider = FutureProvider.autoDispose.family<AirLevel, (double, double)>((ref, p) async {
  final point = await ref.read(airRepositoryProvider).currentAt(GeoPoint(p.$1, p.$2));
  return point.level;
});

final routeConditionsProvider = Provider.autoDispose<RouteConditions?>((ref) {
  final s = ref.watch(routesProvider);
  final dest = s.destination;
  if (dest == null) return null;
  final air = ref.watch(airAtProvider((dest.lat, dest.lng))).valueOrNull;
  final map = ref.watch(airMapProvider).valueOrNull ?? const <AirMapPoint>[];
  final route = s.selectedRoute;
  final climate = s.result?.climate;
  return RouteConditions(
    destinationAir: air,
    smokeOnRoute: route == null ? const [] : smokeAlong(route.points, map),
    sun: climate != null && isStrongSun(climate) ? climate : null,
  );
});

/// Avisos de fumaça e sol forte para o destino escolhido.
class ConditionsWarning extends ConsumerWidget {
  const ConditionsWarning({super.key, required this.conditions, required this.destination});
  final RouteConditions conditions;
  final Place destination;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = conditions;
    final persona = ref.watch(personaProvider);
    final worst = c.worstAir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (worst != null && worst.isBad)
          _Warning(
            icon: Icons.air,
            color: Tokens.air(worst, sunMode: context.sunMode),
            title: c.smokeAtDestination
                ? (worst.index >= AirLevel.muitoRuim.index
                    ? 'Ar muito comprometido no destino'
                    : 'Fumaça no destino')
                : 'O caminho passa por fumaça',
            text: '${c.smokeAtDestination ? 'Em ${destination.name}' : 'Trecho ${zoneOf(c.smokeOnRoute.first.lat, c.smokeOnRoute.first.lng)}'}'
                ' o ar está ${worst.label.toLowerCase()}. ${adviseAir(worst, persona).message}',
          ),
        if (c.sun != null)
          _Warning(
            icon: Icons.wb_sunny,
            color: Tokens.sol,
            title: 'Sol forte no caminho (UV ${c.sun!.uvIndex.round()})',
            text: 'Use protetor solar, boné e leve água. Prefira a rota com mais sombra.',
          ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.icon, required this.color, required this.title, required this.text});
  final IconData icon;
  final Color color;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(text, style: t.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
