import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';

/// Perfil que o agente aprende com o uso. Fica salvo no aparelho
/// e é sincronizado com o servidor quando houver conexão.
class AdaptiveController extends Notifier<AdaptiveProfile> {
  static const _key = 'adaptive_profile';

  @override
  AdaptiveProfile build() {
    final m = ref.read(localStoreProvider).readMap(_key);
    return m == null ? const AdaptiveProfile() : AdaptiveProfile.fromJson(m);
  }

  Future<void> recordComfort(ComfortFeedback f, RiskLevel predicted) =>
      _save(state.withComfortFeedback(f, predicted));

  Future<void> recordRouteChoice({
    required double chosenShade,
    required double fastestShade,
    required double durationRatio,
  }) =>
      _save(state.withRouteChoice(
        chosenShade: chosenShade,
        fastestShade: fastestShade,
        chosenDurationRatio: durationRatio,
      ));

  Future<void> recordDeparture(DateTime when) => _save(state.withDeparture(when));

  Future<void> reset() async {
    await _save(const AdaptiveProfile());
    await ref.read(auditLoggerProvider).log('aprendizado_reiniciado', approved: true);
  }

  /// Usa a versão com mais aprendizado entre aparelho e servidor.
  Future<void> syncFromServer() async {
    try {
      final remote = AdaptiveProfile.fromJson(
        (await ref.read(apiClientProvider).get('/profile/adaptive') as Map).cast<String, dynamic>(),
      );
      final remoteWeight = remote.feedbackCount + remote.routeChoices;
      final localWeight = state.feedbackCount + state.routeChoices;
      if (remoteWeight > localWeight) {
        state = remote;
        await ref.read(localStoreProvider).writeMap(_key, remote.toJson());
      } else if (localWeight > remoteWeight) {
        await ref.read(apiClientProvider).put('/profile/adaptive', state.toJson());
      }
    } catch (_) {}
  }

  Future<void> _save(AdaptiveProfile p) async {
    state = p;
    await ref.read(localStoreProvider).writeMap(_key, p.toJson());
    try {
      await ref.read(apiClientProvider).put('/profile/adaptive', p.toJson());
    } catch (_) {/* sincroniza depois */}
  }
}

final adaptiveProvider = NotifierProvider<AdaptiveController, AdaptiveProfile>(AdaptiveController.new);
