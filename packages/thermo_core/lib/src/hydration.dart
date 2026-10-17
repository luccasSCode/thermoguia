import 'models.dart';

/// Meta diária de água (ml), considerando perfil e o pior risco do dia.
int hydrationGoalMl(Persona persona, RiskLevel peakRisk) {
  var goal = 2000.0;
  goal += (persona.met - 3) * 250; // mais esforço, mais suor
  goal += peakRisk.index * 250;
  if (persona.worksOutdoors) goal += 500;
  return (goal / 50).round() * 50;
}

/// Quanto o usuário já deveria ter bebido até agora (meta distribuída 6h–22h).
int expectedWaterByNow(int goalMl, DateTime now) {
  final h = now.hour + now.minute / 60;
  final progress = ((h - 6) / 16).clamp(0.0, 1.0);
  return (goalMl * progress).round();
}

/// Intervalo entre lembretes de hidratação durante exposição.
int hydrationReminderMinutes(RiskLevel level, Persona persona) {
  final base = switch (level) {
    RiskLevel.baixo => 60,
    RiskLevel.moderado => 40,
    RiskLevel.alto => 25,
    RiskLevel.muitoAlto => 20,
    RiskLevel.extremo => 15,
  };
  final effortCut = persona.met >= 5 ? 5 : 0;
  return (base - effortCut).clamp(10, 90);
}
