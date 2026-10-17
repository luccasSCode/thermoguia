import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../climate/climate_providers.dart';
import '../outdoor/outdoor_session_controller.dart';

enum SunModeSetting {
  auto('Automático'),
  on('Sempre ligado'),
  off('Desligado');

  const SunModeSetting(this.label);
  final String label;
}

class SunModeController extends Notifier<SunModeSetting> {
  @override
  SunModeSetting build() {
    final saved = ref.read(localStoreProvider).getString('sun_mode');
    return SunModeSetting.values.firstWhere((s) => s.name == saved, orElse: () => SunModeSetting.auto);
  }

  Future<void> set(SunModeSetting s) async {
    state = s;
    await ref.read(localStoreProvider).setString('sun_mode', s.name);
  }
}

final sunModeSettingProvider = NotifierProvider<SunModeController, SunModeSetting>(SunModeController.new);

/// Modo Sol Forte ativo agora?
///
/// No automático, liga quando o sol está forte (UV 7 ou mais com pouca
/// nuvem) ou quando a pessoa está na rua durante o dia — situações em que
/// o brilho da tela compete com a luz do sol.
final sunModeActiveProvider = Provider<bool>((ref) {
  switch (ref.watch(sunModeSettingProvider)) {
    case SunModeSetting.on:
      return true;
    case SunModeSetting.off:
      return false;
    case SunModeSetting.auto:
      final c = ref.watch(climateProvider).valueOrNull?.current;
      if (c == null || !c.isDay) return false;
      final outside = ref.watch(outdoorSessionProvider.select((s) => s.active));
      return (c.uvIndex >= 7 && c.cloudCover < 70) || (outside && c.uvIndex >= 4);
  }
});
