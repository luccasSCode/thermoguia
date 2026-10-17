import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../climate/climate_providers.dart';
import '../session/presentation/session_controller.dart';

/// Quando uma sugestão faz mais sentido.
enum When { sempre, dia, noite, chuva, calorForte }

class Suggestion {
  const Suggestion(this.text, this.icon, {this.personas = const {}, this.when = When.sempre});
  final String text;
  final IconData icon;

  /// Perfis para quem a pergunta é mais útil (vazio = todos).
  final Set<Persona> personas;
  final When when;
}

/// Banco de perguntas prontas. Todas têm resposta concreta no assistente,
/// mesmo sem IA.
const suggestionBank = <Suggestion>[
  Suggestion('Qual o melhor horário para caminhar hoje?', Icons.schedule),
  Suggestion('Quanto de água eu devo beber agora?', Icons.water_drop_outlined),
  Suggestion('Onde posso me refrescar perto daqui?', Icons.ac_unit),
  Suggestion('Vou pedalar 5 km ao meio-dia. É seguro?', Icons.directions_bike, personas: {Persona.ciclista}),
  Suggestion('Que roupa eu visto para sair agora?', Icons.checkroom, when: When.dia),
  Suggestion('Preciso levar guarda-chuva hoje?', Icons.umbrella_outlined, when: When.chuva),
  Suggestion('Dá para levar meu cachorro para passear agora?', Icons.pets),
  Suggestion('Qual a hora mais quente de hoje?', Icons.local_fire_department_outlined, when: When.dia),
  Suggestion('Vou ficar 2 horas na rua. O que levo na mochila?', Icons.backpack_outlined),
  Suggestion('Que horas o sol fica mais fraco?', Icons.wb_twilight, when: When.dia),
  Suggestion('Posso correr no fim da tarde?', Icons.directions_run),
  Suggestion('Vai refrescar mais tarde?', Icons.thermostat, when: When.calorForte),
  Suggestion('Quais sinais mostram que passei do limite?', Icons.health_and_safety_outlined),
  Suggestion('Como proteger uma pessoa idosa do calor?', Icons.elderly, personas: {Persona.idoso}),
  Suggestion('Como cuidar de uma criança num dia assim?', Icons.child_care),
  Suggestion('Como deixar a casa mais fresca para dormir?', Icons.bedtime_outlined, when: When.noite),
  Suggestion('O que é bom comer num dia quente?', Icons.restaurant_outlined),
  Suggestion('Quanto tempo posso ficar no sol sem me queimar?', Icons.wb_sunny_outlined, when: When.dia),
  Suggestion('Vou fazer entregas por 4 horas. O que levo?', Icons.delivery_dining, personas: {Persona.entregador}),
  Suggestion('Fico vendendo no sol por 6 horas. Quanto de água preciso?', Icons.storefront_outlined,
      personas: {Persona.vendedor}),
  Suggestion('Vou andar 8 km hoje. Qual o melhor horário?', Icons.markunread_mailbox_outlined,
      personas: {Persona.carteiro, Persona.pedestre}),
  Suggestion('Me dá uma dica rápida para hoje', Icons.tips_and_updates_outlined),
];

/// Situação atual, para ordenar as sugestões.
class SuggestionContext {
  const SuggestionContext({required this.persona, required this.night, required this.rain, required this.hot});
  final Persona persona;
  final bool night;
  final bool rain;
  final bool hot;

  bool fits(When w) => switch (w) {
        When.sempre => true,
        When.dia => !night,
        When.noite => night,
        When.chuva => rain,
        When.calorForte => hot,
      };
}

final suggestionContextProvider = Provider<SuggestionContext>((ref) {
  final climate = ref.watch(climateProvider).valueOrNull;
  final risk = ref.watch(riskProvider);
  final now = DateTime.now();
  final night = climate == null ? (now.hour < 6 || now.hour >= 18) : !climate.current.isDay;
  final rain = climate != null &&
      climate.hourly.where((h) => h.time.isAfter(now)).take(12).any((h) => h.precipitationProb >= 40);
  return SuggestionContext(
    persona: ref.watch(personaProvider),
    night: night,
    rain: rain,
    hot: risk != null && risk.level.index >= RiskLevel.alto.index,
  );
});

/// Escolhe [count] sugestões: primeiro as do perfil e do momento, depois as
/// gerais, embaralhadas por [seed] (o botão "Outras ideias" troca a semente).
List<Suggestion> pickSuggestions(SuggestionContext ctx, {required int count, int seed = 0, Set<String> skip = const {}}) {
  final rnd = math.Random(seed);
  final pool = suggestionBank.where((s) => !skip.contains(s.text) && ctx.fits(s.when)).toList()..shuffle(rnd);
  int rank(Suggestion s) =>
      (s.personas.contains(ctx.persona) ? 4 : 0) + (s.when != When.sempre ? 2 : 0) - (s.personas.isNotEmpty && !s.personas.contains(ctx.persona) ? 3 : 0);
  // Na primeira tela, o que é do perfil vem antes; nas trocas, mistura mais.
  pool.sort((a, b) => seed == 0 ? rank(b).compareTo(rank(a)) : (rank(b).clamp(-1, 1)).compareTo(rank(a).clamp(-1, 1)));
  return pool.take(count).toList();
}
