import 'heat_index.dart';
import 'hydration.dart';
import 'models.dart';

/// Motor de decisão do agente: transforma clima + contexto em risco
/// e recomendações acionáveis.
///
/// O índice efetivo parte do índice de calor oficial e soma ajustes
/// explicáveis — cada parcela pode ser mostrada ao usuário.
class RiskEngine {
  const RiskEngine();

  /// Limiares calibrados para a realidade de Manaus (índice efetivo, °C).
  static const thresholds = <RiskLevel, double>{
    RiskLevel.moderado: 27,
    RiskLevel.alto: 32,
    RiskLevel.muitoAlto: 38,
    RiskLevel.extremo: 45,
  };

  RiskLevel levelFor(double effectiveC) {
    var level = RiskLevel.baixo;
    thresholds.forEach((l, t) {
      if (effectiveC >= t) level = l;
    });
    return level;
  }

  /// Parcelas do índice efetivo, para explicar a decisão do agente.
  Map<String, double> breakdown(ClimateSnapshot c, UserContext u) {
    final parts = <String, double>{};
    if (c.isDay && c.uvIndex >= 6) {
      final cloudFactor = 1 - (c.cloudCover / 100) * 0.6;
      parts['Radiação UV'] = (c.uvIndex >= 11 ? 3.0 : c.uvIndex >= 8 ? 2.0 : 1.0) * cloudFactor;
    }
    if (u.exposureMinutesToday > 0) {
      parts['Tempo ao sol hoje'] = (u.exposureMinutesToday / 30 * 0.7).clamp(0, 4).toDouble();
    }
    final effort = (u.persona.met - 2.5) * 0.8;
    if (effort > 0) parts['Esforço físico'] = effort;

    final goal = hydrationGoalMl(u.persona, RiskLevel.alto);
    final expected = expectedWaterByNow(goal, c.time);
    if (expected > 0 && u.waterMlToday < expected) {
      final deficit = (expected - u.waterMlToday) / expected;
      parts['Pouca água hoje'] = (deficit * 2).clamp(0, 2).toDouble();
    }
    if (u.persona == Persona.idoso) parts['Faixa etária'] = 1.5;
    if (u.sensitivityOffset.abs() >= 0.1) {
      parts['Sua sensibilidade'] = u.sensitivityOffset;
    }
    if (c.windKmh >= 15) parts['Vento'] = -1.0;
    return parts;
  }

  RiskAssessment assess(ClimateSnapshot c, UserContext u) {
    final hi = heatIndexC(c.temperatureC, c.humidity);
    final parts = breakdown(c, u);
    final effective = hi + parts.values.fold<double>(0, (a, b) => a + b);
    final level = levelFor(effective);
    final score = ((effective - 24) / (50 - 24) * 100).clamp(0, 100).round();

    return RiskAssessment(
      heatIndexC: hi,
      effectiveIndexC: effective,
      level: level,
      score: score,
      hydrationIntervalMin: hydrationReminderMinutes(level, u.persona),
      waterGoalMl: hydrationGoalMl(u.persona, level),
      recommendations: _recommend(c, u, level),
    );
  }

  List<Recommendation> _recommend(ClimateSnapshot c, UserContext u, RiskLevel level) {
    final recs = <Recommendation>[];
    final interval = hydrationReminderMinutes(level, u.persona);
    final goal = hydrationGoalMl(u.persona, level);
    final expected = expectedWaterByNow(goal, c.time);

    if (u.waterMlToday < expected) {
      final missing = ((expected - u.waterMlToday) / 50).round() * 50;
      recs.add(Recommendation(
        id: 'agua-deficit',
        kind: RecommendationKind.hidratacao,
        title: 'Beba água agora',
        message: 'Faltam cerca de $missing ml para você estar em dia. '
            'Depois, um copo a cada $interval minutos.',
        priority: 60 + level.index * 8,
      ));
    }

    if (level.index >= RiskLevel.alto.index && c.isDay) {
      recs.add(Recommendation(
        id: 'sombra',
        kind: RecommendationKind.sombra,
        title: 'Use a Rota Fresca',
        message: 'Nos deslocamentos, prefira trajetos com árvores e marquises. '
            'Pausas de 5 minutos na sombra reduzem o acúmulo de calor.',
        priority: 55 + level.index * 8,
      ));
    }

    if (c.isDay && c.uvIndex >= 8) {
      recs.add(Recommendation(
        id: 'uv',
        kind: RecommendationKind.roupa,
        title: 'UV ${c.uvIndex.round()}: proteja a pele',
        message: 'Protetor solar, boné ou chapéu e roupas claras e leves. '
            'Reaplique o protetor a cada 2 horas.',
        priority: 45 + c.uvIndex.round(),
      ));
    }

    if (u.exposureMinutesToday >= 90 && level.index >= RiskLevel.alto.index) {
      recs.add(Recommendation(
        id: 'pausa',
        kind: RecommendationKind.saude,
        title: 'Hora de uma pausa longa',
        message: 'Você já soma ${u.exposureMinutesToday} min ao sol hoje. '
            'Fique 15 minutos em local fresco ou climatizado.',
        priority: 80,
      ));
    }

    if (level == RiskLevel.extremo || (level == RiskLevel.muitoAlto && u.persona == Persona.idoso)) {
      recs.add(const Recommendation(
        id: 'sinais',
        kind: RecommendationKind.saude,
        title: 'Atenção aos sinais do corpo',
        message: 'Tontura, dor de cabeça forte, náusea ou confusão são sinais de '
            'alerta. Pare, procure sombra e use "Estou passando mal" se precisar.',
        priority: 95,
      ));
    }

    if (c.precipitationProb >= 60) {
      recs.add(Recommendation(
        id: 'chuva',
        kind: RecommendationKind.chuva,
        title: 'Chuva provável (${c.precipitationProb.round()}%)',
        message: 'A chuva costuma aliviar o calor em Manaus, mas leve '
            'guarda-chuva e cuidado com alagamentos.',
        priority: 35,
      ));
    }

    if (u.persona == Persona.ciclista && level.index >= RiskLevel.muitoAlto.index) {
      recs.add(const Recommendation(
        id: 'ciclista',
        kind: RecommendationKind.rota,
        title: 'Pedale mais leve',
        message: 'Reduza o ritmo em subidas e leve duas garrafas de água.',
        priority: 50,
      ));
    }

    recs.sort((a, b) => b.priority.compareTo(a.priority));
    return recs;
  }
}
