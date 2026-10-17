import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../climate/climate_providers.dart';
import '../hydration/hydration_controller.dart';
import '../outdoor/outdoor_session_controller.dart';

class Briefing {
  const Briefing(this.text, this.fromAi);
  final String text;
  final bool fromAi;
}

/// Resumo do agente para a tela inicial. Depende só da localização
/// para não ser refeito a cada copo de água registrado.
final briefingProvider = FutureProvider.autoDispose<Briefing>((ref) async {
  final loc = await ref.watch(userLocationProvider.future);
  final data = await ref.read(apiClientProvider).get('/ai/briefing', query: {
    'lat': loc.point.lat,
    'lng': loc.point.lng,
    'exposureMinutes': ref.read(outdoorSessionProvider).minutesToday,
    'waterMl': ref.read(hydrationProvider).totalMl,
  }) as Map;
  return Briefing(data['text'] as String, data['source'] == 'claude');
});
