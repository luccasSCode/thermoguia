import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../air/air_providers.dart';
import '../climate/climate_providers.dart';
import '../session/presentation/session_controller.dart';

/// Quando uma sugestão faz mais sentido.
enum When { sempre, dia, noite, chuva, calorForte, fumaca }

/// Assunto da pergunta: a lista infinita alterna entre os dois.
enum Topic { calor, fumaca }

final _smokeWords = RegExp(r'fumaça|queimada|máscara|qualidade do ar|janelas|Hora Segura|olhos e garganta|o ar\b',
    caseSensitive: false);

class Suggestion {
  const Suggestion(this.text, this.icon, {this.personas = const {}, this.when = When.sempre});
  final String text;
  final IconData icon;

  /// Perfis para quem a pergunta é mais útil (vazio = todos).
  final Set<Persona> personas;
  final When when;

  Topic get topic => when == When.fumaca || _smokeWords.hasMatch(text) ? Topic.fumaca : Topic.calor;
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
  // Sol e sombra.
  Suggestion('Qual lado da rua tem mais sombra agora?', Icons.park_outlined, when: When.dia),
  Suggestion('Andar pela sombra faz quanta diferença no calor?', Icons.forest_outlined),
  Suggestion('Preciso passar protetor solar agora?', Icons.sanitizer_outlined, when: When.dia),
  Suggestion('Até que horas o sol está forte hoje?', Icons.wb_sunny_outlined, when: When.dia),
  // Fumaça das queimadas.
  Suggestion('Como está a fumaça agora?', Icons.air),
  Suggestion('Preciso usar máscara para sair hoje?', Icons.masks_outlined, when: When.fumaca),
  Suggestion('Quando a qualidade do ar vai melhorar?', Icons.update, when: When.fumaca),
  Suggestion('Posso abrir as janelas de casa agora?', Icons.window_outlined, when: When.fumaca),
  Suggestion('Rua arborizada protege da fumaça?', Icons.park_outlined, when: When.fumaca),
  Suggestion('Respirar essa fumaça equivale a quantos cigarros?', Icons.smoking_rooms_outlined, when: When.fumaca),
  Suggestion('Meus olhos e garganta estão ardendo. O que faço?', Icons.visibility_outlined, when: When.fumaca),
  Suggestion('Dá para pedalar com essa fumaça?', Icons.directions_bike, personas: {Persona.ciclista}, when: When.fumaca),
  Suggestion('Como proteger uma pessoa idosa da fumaça?', Icons.elderly, personas: {Persona.idoso}, when: When.fumaca),
  Suggestion('Trabalho na rua o dia todo. Como me proteger da fumaça?', Icons.masks_outlined,
      personas: {Persona.entregador, Persona.vendedor, Persona.carteiro}, when: When.fumaca),
  Suggestion('Qual a Hora Segura para sair hoje?', Icons.verified_user_outlined),
  // Calor em Manaus e previsão do tempo.
  Suggestion('Por que Manaus é tão quente e abafada?', Icons.thermostat),
  Suggestion('O que é a ilha de calor na cidade?', Icons.location_city_outlined),
  Suggestion('Quais bairros esquentam mais em Manaus?', Icons.map_outlined),
  Suggestion('A umidade alta piora a sensação de calor?', Icons.water_outlined),
  Suggestion('Qual vai ser a temperatura máxima hoje?', Icons.device_thermostat, when: When.dia),
  Suggestion('Até que horas vai fazer calor hoje?', Icons.schedule, when: When.dia),
  Suggestion('Qual a sensação térmica agora?', Icons.thermostat_auto_outlined),
  Suggestion('Qual o índice UV agora?', Icons.wb_sunny_outlined, when: When.dia),
  Suggestion('Como saber se estou desidratado?', Icons.water_drop_outlined),
  Suggestion('Ventilador ajuda mesmo no calor forte?', Icons.wind_power_outlined),
  Suggestion('Como vai estar o tempo amanhã?', Icons.calendar_today_outlined),
  Suggestion('Vai chover forte hoje? Tem risco de alagamento?', Icons.flood_outlined),
  // Fumaça das queimadas.
  Suggestion('Por que tem tanta fumaça em Manaus?', Icons.local_fire_department_outlined),
  Suggestion('De onde vem a fumaça das queimadas?', Icons.public),
  Suggestion('Quando acaba a temporada de queimadas?', Icons.event_outlined),
  Suggestion('Qual máscara protege da fumaça?', Icons.masks_outlined),
  Suggestion('Máscara de pano protege da fumaça?', Icons.masks_outlined),
  Suggestion('Como denunciar uma queimada?', Icons.report_outlined),
  Suggestion('Quem tem asma pode sair com essa fumaça?', Icons.medical_services_outlined),
  Suggestion('A fumaça faz mal para crianças?', Icons.child_care),
  Suggestion('Posso fazer exercício ao ar livre com fumaça?', Icons.directions_run),
  Suggestion('A chuva ajuda a limpar a fumaça?', Icons.grain),
  Suggestion('Como limpar o ar dentro de casa?', Icons.home_outlined),
];

/// Situação atual, para ordenar as sugestões.
class SuggestionContext {
  const SuggestionContext({
    required this.persona,
    required this.night,
    required this.rain,
    required this.hot,
    this.smoke = false,
  });
  final Persona persona;
  final bool night;
  final bool rain;
  final bool hot;

  /// Ar ruim ou pior agora ou nas próximas horas.
  final bool smoke;

  bool fits(When w) => switch (w) {
        When.sempre => true,
        When.dia => !night,
        When.noite => night,
        When.chuva => rain,
        When.calorForte => hot,
        When.fumaca => smoke,
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
    smoke: ref.watch(airProvider).valueOrNull?.next(12).any((h) => h.level.isBad) ?? false,
  );
});

/// Escolhe [count] sugestões: primeiro as do perfil e do momento, depois as
/// gerais, embaralhadas por [seed] (o botão "Outras ideias" troca a semente).
List<Suggestion> pickSuggestions(SuggestionContext ctx, {required int count, int seed = 0, Set<String> skip = const {}}) {
  final rnd = math.Random(seed);
  final pool = suggestionBank.where((s) => !skip.contains(s.text) && ctx.fits(s.when)).toList()..shuffle(rnd);
  int rank(Suggestion s) =>
      (s.personas.contains(ctx.persona) ? 4 : 0) +
      (s.when != When.sempre ? 2 : 0) +
      // No período de fumaça, as perguntas sobre o ar vêm primeiro.
      (s.when == When.fumaca ? 3 : 0) -
      (s.personas.isNotEmpty && !s.personas.contains(ctx.persona) ? 3 : 0);
  // Na primeira tela, o que é do perfil vem antes; nas trocas, mistura mais.
  pool.sort((a, b) => seed == 0 ? rank(b).compareTo(rank(a)) : (rank(b).clamp(-1, 1)).compareTo(rank(a).clamp(-1, 1)));
  return pool.take(count).toList();
}

/// Mais perguntas para a rolagem da tela inicial: alterna calor e fumaça e não
/// repete as de [skip]. Mostra também as de chuva, fumaça e calor forte fora
/// do momento (a resposta usa os dados de agora); só respeita dia/noite e perfil.
List<Suggestion> moreSuggestions(SuggestionContext ctx, {required int page, int count = 6, Set<String> skip = const {}}) {
  final rnd = math.Random(page * 7919 + 1);
  bool ok(Suggestion s) =>
      !skip.contains(s.text) &&
      (s.personas.isEmpty || s.personas.contains(ctx.persona)) &&
      switch (s.when) {
        When.dia => !ctx.night,
        When.noite => ctx.night,
        _ => true,
      };
  final heat = suggestionBank.where((s) => ok(s) && s.topic == Topic.calor).toList()..shuffle(rnd);
  final smoke = suggestionBank.where((s) => ok(s) && s.topic == Topic.fumaca).toList()..shuffle(rnd);
  final out = <Suggestion>[];
  while (out.length < count && (heat.isNotEmpty || smoke.isNotEmpty)) {
    final takeSmoke = out.length.isOdd ? smoke.isNotEmpty : heat.isEmpty;
    out.add((takeSmoke ? smoke : heat).removeAt(0));
  }
  return out;
}
