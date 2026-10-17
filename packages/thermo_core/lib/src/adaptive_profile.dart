import 'dart:math' as math;

import 'models.dart';

/// Como o usuário se sentiu ao final de um deslocamento.
enum ComfortFeedback {
  confortavel('Tranquilo', -0.6),
  calor('Senti calor', 0.4),
  muitoCalor('Passei mal de calor', 1.2);

  const ComfortFeedback(this.label, this.signal);
  final String label;

  /// Direção do ajuste de sensibilidade.
  final double signal;
}

/// Perfil que o agente aprende com o uso.
///
/// * [sensitivityOffset]: quanto o usuário sente mais (+) ou menos (−) calor
///   que a média, em °C. Ajustado pelo feedback pós-trajeto.
/// * [shadePreference]: peso dado à sombra versus tempo de trajeto (0–1).
///   Ajustado pelas rotas que o usuário de fato escolhe.
/// * [hourHistogram]: horários em que o usuário costuma sair, usado para
///   avisos antecipados ("você costuma sair às 7h; amanhã às 7h o risco é...").
class AdaptiveProfile {
  const AdaptiveProfile({
    this.sensitivityOffset = 0,
    this.shadePreference = 0.6,
    this.feedbackCount = 0,
    this.routeChoices = 0,
    this.hourHistogram = const {},
  });

  final double sensitivityOffset;
  final double shadePreference;
  final int feedbackCount;
  final int routeChoices;
  final Map<int, int> hourHistogram;

  /// Taxa de aprendizado decrescente: aprende rápido no início e
  /// estabiliza com o tempo, sem nunca congelar.
  double get _lr => math.max(0.15, 1 / (feedbackCount + 2));

  AdaptiveProfile withComfortFeedback(ComfortFeedback f, RiskLevel predicted) {
    // Se o agente previa risco alto e a pessoa estava tranquila, o sinal pesa
    // mais; se previa baixo e ela passou mal, também. Surpresas ensinam mais.
    final surprise = switch (f) {
      ComfortFeedback.confortavel => 1 + predicted.index * 0.25,
      ComfortFeedback.calor => 1.0,
      ComfortFeedback.muitoCalor => 1 + (4 - predicted.index) * 0.25,
    };
    final next = (sensitivityOffset + _lr * f.signal * surprise).clamp(-3.0, 3.0);
    return copyWith(sensitivityOffset: next, feedbackCount: feedbackCount + 1);
  }

  /// [chosenShade] e [chosenDurationRatio] da rota escolhida, comparada à mais
  /// rápida (razão 1.0 = mesma duração).
  AdaptiveProfile withRouteChoice({
    required double chosenShade,
    required double fastestShade,
    required double chosenDurationRatio,
  }) {
    double target;
    if (chosenDurationRatio > 1.05 && chosenShade > fastestShade + 0.05) {
      target = 0.9; // aceitou andar mais por sombra
    } else if (chosenDurationRatio <= 1.02) {
      target = 0.3; // prefere o caminho mais curto
    } else {
      return copyWith(routeChoices: routeChoices + 1);
    }
    final lr = math.max(0.1, 1 / (routeChoices + 3));
    final next = shadePreference + lr * (target - shadePreference);
    return copyWith(shadePreference: next.clamp(0.1, 0.95), routeChoices: routeChoices + 1);
  }

  AdaptiveProfile withDeparture(DateTime when) {
    final h = Map<int, int>.from(hourHistogram);
    h[when.hour] = (h[when.hour] ?? 0) + 1;
    return copyWith(hourHistogram: h);
  }

  /// Horários mais frequentes de saída (até 2), se houver dados suficientes.
  List<int> get habitualHours {
    final total = hourHistogram.values.fold<int>(0, (a, b) => a + b);
    if (total < 4) return const [];
    final sorted = hourHistogram.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return sorted.where((e) => e.value / total >= 0.2).take(2).map((e) => e.key).toList();
  }

  AdaptiveProfile copyWith({
    double? sensitivityOffset,
    double? shadePreference,
    int? feedbackCount,
    int? routeChoices,
    Map<int, int>? hourHistogram,
  }) =>
      AdaptiveProfile(
        sensitivityOffset: sensitivityOffset ?? this.sensitivityOffset,
        shadePreference: shadePreference ?? this.shadePreference,
        feedbackCount: feedbackCount ?? this.feedbackCount,
        routeChoices: routeChoices ?? this.routeChoices,
        hourHistogram: hourHistogram ?? this.hourHistogram,
      );

  factory AdaptiveProfile.fromJson(Map<String, dynamic> j) => AdaptiveProfile(
        sensitivityOffset: (j['sensitivityOffset'] as num?)?.toDouble() ?? 0,
        shadePreference: (j['shadePreference'] as num?)?.toDouble() ?? 0.6,
        feedbackCount: (j['feedbackCount'] as num?)?.toInt() ?? 0,
        routeChoices: (j['routeChoices'] as num?)?.toInt() ?? 0,
        hourHistogram: ((j['hourHistogram'] as Map?) ?? const {}).map(
          (k, v) => MapEntry(int.parse('$k'), (v as num).toInt()),
        ),
      );

  Map<String, dynamic> toJson() => {
        'sensitivityOffset': sensitivityOffset,
        'shadePreference': shadePreference,
        'feedbackCount': feedbackCount,
        'routeChoices': routeChoices,
        'hourHistogram': hourHistogram.map((k, v) => MapEntry('$k', v)),
      };
}
