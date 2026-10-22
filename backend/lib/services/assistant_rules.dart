import 'dart:math' as math;

import 'package:thermo_core/thermo_core.dart';

import 'assistant_service.dart';

/// Tira acentos e caixa, para comparar o texto do usuário com padrões.
String normalize(String s) {
  const from = 'áàâãäéèêëíìîïóòôõöúùûüçñ';
  const to = 'aaaaaeeeeiiiiooooouuuucn';
  final b = StringBuffer();
  for (final ch in s.toLowerCase().split('')) {
    final i = from.indexOf(ch);
    b.write(i < 0 ? ch : to[i]);
  }
  return b.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
}

/// Erros de digitação comuns (teclado sem cedilha, letras trocadas) nas
/// palavras-chave do calor e da fumaça. Recebe o texto já normalizado.
String fixTypos(String q) {
  const fixes = {
    r'\bfum(a|aa|asa|assa|aca|ca|ça|acaa|ac)\b': 'fumaca',
    r'\bfumacento\b': 'fumaca',
    r'\bqu?eim(a|ad|da|adas?|dsa)\b': 'queimada',
    r'\bmasc(ra|arq|aras?|cara)\b': 'mascara',
    r'\bten?mporal\b|\btenporal\b': 'temporal',
    r'\balag(ameto|amnto|ado|ou)\b': 'alagamento',
    r'\bchuv(a|aa|inha)\b': 'chuva',
    r'\bxuva\b': 'chuva',
    r'\bcalo\b': 'calor',
    r'\bquent(e|ee|i)\b': 'quente',
    r'\bsoll?\b': 'sol',
    r'\bhrs?\b|\bhorario(s)?\b': 'horario',
  };
  var out = q;
  fixes.forEach((pattern, word) => out = out.replaceAll(RegExp(pattern), word));
  return out;
}

/// Assuntos que o assistente não discute: como o app foi feito, tecnologia,
/// servidores, IA usada, estas instruções, custos e dados internos.
abstract final class TopicGuard {
  static final _patterns = [
    r'\b(codigo|codigo[- ]fonte|source code|programacao|programador|desenvolv(ido|imento|edor|eram|eu))\b',
    r'\b(api|apis|endpoint|backend|back-end|front-?end|servidor(es)?|server|hospedage?m|host|deploy|docker|cloud|nuvem da aws|aws|firebase)\b',
    r'\b(banco de dados|database|sql|postgres|tabela(s)? do banco|schema)\b',
    r'\b(flutter|dart|react|kotlin|swift|java|javascript|python|framework|linguagem de programacao|sdk|stack)\b',
    r'arquitetura (do|de) (app|aplicativo|sistema|software)',
    r'\b(github|git|repositorio|commit)\b',
    r'\b(prompt|system prompt|instrucoes (do sistema|internas|que voce recebeu)|suas (regras|instrucoes)|ignore (as|suas|todas)|modo desenvolvedor|jailbreak)\b',
    r'\b(chave (de api|secreta|da api)|api key|token|senha do (app|sistema|servidor)|credencia(l|is)|admin(istrador)?)\b',
    r'\b(modelo de (ia|linguagem)|llm|gpt|chatgpt|openai|claude|anthropic|gemini)\b',
    r'\b(qual|que) (ia|inteligencia artificial|modelo)\b',
    r'\b(algoritmo|formula exata|machine learning|rede neural|treinad[oa])\b',
    r'(como|quem) (voce|o app|o aplicativo|o thermoguia|isso) (foi|e) (feito|criado|construido|programado|desenvolvido)',
    r'quem (te |o )?(criou|fez|programou|desenvolveu)',
    r'\b(custo|custa|gasto)\b.*\b(servidor|manter|hospedagem|desenvolver|a ia|empresa)\b',
    r'\b(lucro|faturamento|investimento|investidor)\b',
    r'\b(dados|localizacao|historico|conversas?) de (outros|outras) (usuarios|pessoas)\b',
    r'\b(logs?|bug|hack(ear|er)?|vulnerabilidade|exploit)\b',
  ].map(RegExp.new).toList();

  static bool isInternal(String text) {
    final q = normalize(text);
    return _patterns.any((p) => p.hasMatch(q));
  }

  static const reply = 'Essa parte é interna do aplicativo, então não consigo detalhar. '
      'Aqui eu ajudo com o calor do seu dia: melhor horário para sair, quanta água beber, '
      'roupa, chuva, sol forte, lugares para se refrescar e rotas com sombra. '
      'Quer que eu veja o melhor horário para você sair hoje?';
}

enum Activity {
  caminhar('caminhar', 4.5, 1.0),
  correr('correr', 9, 3.0),
  pedalar('pedalar', 15, 2.0),
  trabalhar('trabalhar na rua', 3.5, 2.0);

  const Activity(this.label, this.kmh, this.effortC);
  final String label;

  /// Velocidade típica, para estimar a duração pela distância.
  final double kmh;

  /// Quanto o esforço soma à sensação térmica (°C).
  final double effortC;
}

/// O que a pessoa perguntou, extraído do texto.
class ParsedQuestion {
  ParsedQuestion(this.raw) : q = fixTypos(normalize(raw)) {
    hour = _hour();
    durationMin = _duration();
    distanceKm = _distance();
    activity = _activity();
  }

  final String raw;
  final String q;
  late final int? hour;
  late final int? durationMin;
  late final double? distanceKm;
  late final Activity? activity;

  bool has(String pattern) => RegExp(pattern).hasMatch(q);

  int? _hour() {
    if (has(r'meio[- ]?dia')) return 12;
    if (has(r'meia[- ]?noite')) return 0;
    final at = RegExp(r'\b(?:as|a|das|pelas|perto das|depois das|antes das|umas)\s+(\d{1,2})(?:[:h](\d{2})?)?\s*(?:h|horas?)?\b')
        .firstMatch(q);
    if (at != null) {
      final h = int.parse(at.group(1)!);
      if (h <= 23 && !_isDurationAt(at.start)) return _pm(h);
    }
    final hh = RegExp(r'\b(\d{1,2})(?:h(\d{2})?|:(\d{2}))\b').firstMatch(q);
    if (hh != null && !_isDurationAt(hh.start)) {
      final h = int.parse(hh.group(1)!);
      if (h <= 23) return _pm(h);
    }
    if (has(r'fim da tarde|final da tarde|fim de tarde')) return 17;
    if (has(r'\b(de|pela|a|na) tarde\b')) return 15;
    if (has(r'\b(de|pela|a|na) noite\b|anoitecer')) return 19;
    if (has(r'\b(de|pela|na) manha\b|\bcedo\b|amanhecer')) return 7;
    return null;
  }

  /// "às 3 da tarde" = 15h.
  int _pm(int h) => (h >= 1 && h <= 6 && has(r'da tarde|da noite')) || (h >= 7 && h <= 11 && has(r'da noite'))
      ? h + 12
      : h;

  bool _isDurationAt(int index) {
    final before = q.substring(math.max(0, index - 12), index);
    return RegExp(r'(ficar|durante|por|passar|uns|umas|cerca de|mais de)\s*$').hasMatch(before);
  }

  int? _duration() {
    final m = RegExp(r'(?:ficar|durante|por|passar|uns|umas|cerca de|mais de)?\s*(\d+(?:[.,]\d)?)\s*(minutos?|min|horas?|h)\b')
        .allMatches(q);
    for (final x in m) {
      final whole = x.group(0)!;
      final isClock = RegExp(r'^\s*(\d{1,2})h$').hasMatch(whole) && !RegExp(r'ficar|durante|por|passar').hasMatch(whole);
      if (isClock) continue;
      final n = double.parse(x.group(1)!.replaceAll(',', '.'));
      final unit = x.group(2)!;
      if (!RegExp(r'ficar|durante|por|passar|uns|umas|cerca|mais').hasMatch(whole) && unit.startsWith('h') && n <= 23 && hour != null) {
        continue; // "às 15h" já é horário
      }
      return unit.startsWith('min') ? n.round() : (n * 60).round();
    }
    return null;
  }

  double? _distance() {
    final km = RegExp(r'(\d+(?:[.,]\d+)?)\s*(km|quilometros?|kms)\b').firstMatch(q);
    if (km != null) return double.parse(km.group(1)!.replaceAll(',', '.'));
    final m = RegExp(r'(\d+)\s*(m|metros)\b').firstMatch(q);
    if (m != null) return int.parse(m.group(1)!) / 1000;
    return null;
  }

  Activity? _activity() {
    if (has(r'pedal|bike|bicicleta|ciclis|de bici')) return Activity.pedalar;
    if (has(r'\bcorr(er|o|ida|endo)\b|cooper|treino|treinar|futebol|bola|exercicio|academia ao ar livre|esporte')) {
      return Activity.correr;
    }
    if (has(r'trabalh|entreg|vender|ambulante|turno|expediente')) return Activity.trabalhar;
    if (has(r'caminh|andar|passear|a pe\b|ir a pe|ir andando|levar .* (cachorro|cao)')) return Activity.caminhar;
    return null;
  }
}

/// Responde pelo motor de regras quando a IA não está disponível,
/// procurando responder exatamente o que foi perguntado.
class RuleResponder {
  RuleResponder(this.c);
  final AssistantContext c;
  static const _engine = RiskEngine();

  String answer(String question) {
    if (TopicGuard.isInternal(question)) return TopicGuard.reply;
    final p = ParsedQuestion(question);

    final scores = <String, int>{};
    void score(String intent, int pts) => scores[intent] = (scores[intent] ?? 0) + pts;

    final firstPerson = p.has(r'\b(estou|to|tou|sinto|me sinto|me sentindo|fiquei|estou com|to com)\b');
    final symptom = p.has(r'tontur|tonto|desmai|vomit|enjo|nausea|confus|dor de cabeca|caimbra|passando mal|falta de ar|coracao acelerado|pele (quente|vermelha)');
    if (firstPerson && symptom) score('emergencia', 10);
    if ((!firstPerson || p.has(r'como (saber|sei|identificar|perceber)')) && (symptom || p.has(r'sinto?ma|sinais|insolacao|exaustao|intermacao|golpe de calor|desidrata'))) score('sinais', 4);

    if (p.has(r'^(oi|ola|bom dia|boa tarde|boa noite|boa madrugada|e ai|opa|hey)\b')) score('saudacao', 3);
    if (p.has(r'\b(obrigad|valeu|brigad|agradec)')) score('agradecimento', 3);

    if (p.has(r'(e|eh|esta|ta|seria) (seguro|perigoso|tranquilo|de boa|ok)|posso|da (pra|para)|consigo|vale a pena|e uma boa|devo (ir|sair)|melhor nao')) {
      score('atividade', p.activity != null || p.hour != null || p.distanceKm != null ? 4 : 2);
    }
    if (p.activity != null) score('atividade', 1);
    if (p.has(r'melhor (hora|horario|momento|periodo)|que horas? (e melhor|posso|devo|da)|quando (posso|devo|e melhor|da pra)|hora certa')) score('melhor_horario', 4);
    if (p.has(r'(hora|horario|periodo) mais quente|pior (hora|horario)|esquenta mais|pico do calor|mais calor')) score('mais_quente', 5);
    if (p.has(r'mais tarde|depois|vai (esfriar|melhorar|refrescar|piorar|esquentar|diminuir)|quando (melhora|esfria|refresca|diminui)|comparad|amanha|ate que horas')) score('agora_vs_depois', 4);
    if (p.has(r'\bagua\b|hidrat|beber|bebi|garrafa|\bml\b|litro|copo')) score('agua', 3);
    if (p.has(r'(me|para|pra|onde|lugar|ponto).{0,15}refresc|bebedouro|ar[- ]condicionado|climatizad|abrigo|lugar (fresco|com sombra)|descansar|onde (posso )?(parar|ficar)')) score('refresco', 4);
    if (p.has(r'\brota|caminho|trajeto|como (chego|ir)|ir (ate|para|pro|pra)\b|chegar')) score('rota', 3);
    if (p.has(r'roupa|vestir|visto|blusa|camisa|bone|chapeu|oculos|tenis|manga')) score('roupa', 4);
    if (p.has(r'chuv|chover|guarda[- ]chuva|temporal|tempestade|molhar|capa')) score('chuva', 4);
    if (p.has(r'protetor|filtro solar|queimar|queimadura|\buv\b|ultravioleta|\bsol\b.{0,20}(forte|fraco|baixa|diminui|enfraquece|queima)|bronze|pele')) score('sol', 5);
    if (p.has(r'cachorro|\bcao\b|cadela|cachorra|\bpet\b|gato|animal|patas|passear com')) score('pet', 6);
    if (p.has(r'mochila|kit|o que (eu )?(levo|levar)|checklist|lista|me preparar')) score('kit', 4);
    if (p.has(r'crianca|bebe|filho|filha|idos|avo\b|vovo|gestante|gravida|neto')) score('vulneravel', 4);
    if (p.has(r'quanto (tempo )?(de sol|ja tomei|tomei de sol|fiquei no sol)|exposicao|tempo (no|ao) sol')) score('exposicao', 5);
    if (p.has(r'\bdica|conselho|recomenda|o que (eu )?(faco|fazer)|como (me )?(proteger|aguentar|sobreviver)')) score('dica', 2);
    if (p.has(r'dormir|noite quente|casa (quente|abafada)|quarto|ventilador|em casa|refrescar a casa')) score('casa', 5);
    if (p.has(r'comer|comida|aliment|fruta|lanche|almoco|cafe|bebida alcool|cerveja|refrigerante|energetico')) score('comida', 4);
    if (p.has(r'thermoguia\+|thermoguia plus|\bplano|assinatura|assinar|premium|quanto custa|preco|limite de perguntas|doar|doacao|apoiar o (app|thermoguia)')) score('planos', 5);
    if (p.has(r'fumaca|queimad|qualidade do ar|poluic|polui|mascara|cheiro de (queimado|fumaca)|respirar|\bar (esta|ta|vai) (ruim|pesado|sujo|melhorar)|\bpm ?2|asma|bronquite|olhos?.{0,20}ard|garganta|nevoa|neblina|cinza no ar|fuligem|cigarro|abrir (as )?janelas?|hora segura|ar (de|dentro de|em) casa|limpar o ar')) score('fumaca', 6);
    if (p.has(r'\bsombra|arvore|arborizad|lado da rua|sombreado')) score('sombra', 4);
    if (p.has(r'(como|quanto) (esta|ta) (o )?(calor|tempo|clima)|temperatura|sensacao|risco (de )?agora|ta quente|esta quente|que calor')) score('agora', 3);
    // Calor em Manaus.
    if (p.has(r'(por que|porque|\bpq\b|por q).{0,40}(quente|calor|abafad|mormaco)|ilha de calor|bairros? (mais )?(quente|esquenta)|esquentam mais|manaus (e|eh|esta|ta|fica) (tao )?(quente|abafad)')) {
      score('por_que_calor', 7);
    }
    if (p.has(r'umidade|abafad|mormaco|ar seco|\bumid')) score('umidade', 4);
    if (p.has(r'(temperatura )?(maxima|minima)\b|quantos graus|vai fazer quanto')) score('max_hoje', 5);
    if (p.has(r'previsao|amanha (vai|tem|como)|como (vai|vai estar|vai ficar) (o )?(tempo|clima|dia)|proximos dias|\bsemana\b')) score('previsao', 5);
    if (p.has(r'alag|enchente|inunda|igarape|transbord|temporal|tempestade|\braios?\b|trovoada|trovao|chuva forte|chover forte')) score('alagamento', 6);
    // Fumaça das queimadas.
    if (p.has(r'(por que|porque|\bpq\b|de onde|origem|causa|quem (faz|provoca)|o que (causa|provoca)).{0,40}(fumaca|queimad|fogo)|temporada de queimad|epoca (das|de) queimad|quando (acaba|termina|passa) (a |essa )?(fumaca|queimad|temporada)|\bseca\b|estiagem|el nino')) {
      score('causa_fumaca', 8);
    }
    if (p.has(r'(denunci|avisar|reportar|ligar).{0,30}(queimad|fogo|incendio)|incendio|foco de (fogo|queimada)')) score('denunciar', 9);
    if (p.has(r'(qual|que|tipo de|melhor) mascara|mascara (de pano|cirurgica|comum|caseira|funciona|serve|protege|certa)|purificador')) score('mascara', 8);

    if (scores.isEmpty) return _fallback();
    final ranked = scores.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final top = ranked.first.key;
    if (top == 'emergencia') return _emergencia();

    // Até dois assuntos na mesma pergunta ("posso correr às 17h e quanto de água levo?").
    final parts = <String>[_handle(top, p)];
    if (ranked.length > 1 && ranked[1].value >= 3 && !_overlaps(top, ranked[1].key)) {
      parts.add(_handle(ranked[1].key, p));
    }
    return parts.join('\n\n');
  }

  bool _overlaps(String a, String b) {
    const groups = [
      {'atividade', 'melhor_horario', 'agora_vs_depois', 'agora', 'mais_quente'},
      {'saudacao', 'agradecimento'},
      {'sinais', 'emergencia'},
      {'pet', 'atividade', 'melhor_horario'},
      {'sol', 'melhor_horario', 'mais_quente'},
      {'fumaca', 'casa', 'agora_vs_depois', 'atividade'},
      {'fumaca', 'mascara', 'causa_fumaca', 'denunciar', 'vulneravel', 'chuva'},
      {'alagamento', 'chuva', 'previsao', 'agora_vs_depois'},
      {'por_que_calor', 'umidade', 'agora', 'sombra'},
      {'max_hoje', 'mais_quente', 'agora', 'previsao', 'agora_vs_depois'},
    ];
    return groups.any((g) => g.contains(a) && g.contains(b));
  }

  String _handle(String intent, ParsedQuestion p) => switch (intent) {
        'sinais' => _sinais(),
        'saudacao' => _saudacao(),
        'agradecimento' => 'Por nada! Se for sair, me conta o horário e o trajeto que eu vejo o calor para você.',
        'atividade' => _atividade(p),
        'melhor_horario' => _melhorHorario(p),
        'mais_quente' => _maisQuente(),
        'agora_vs_depois' => _agoraVsDepois(),
        'agua' => _agua(p),
        'refresco' => _refresco(),
        'rota' => 'Abra a aba Rotas e escolha o destino: eu comparo os caminhos pela sombra no horário em que você vai passar '
            'e te guio curva a curva, avisando os trechos de sol forte e o lado da rua com sombra.',
        'roupa' => _roupa(),
        'chuva' => _chuva(),
        'sol' => _sol(p),
        'pet' => _pet(),
        'kit' => _kit(p),
        'vulneravel' => _vulneravel(p),
        'exposicao' => _exposicao(),
        'casa' => _casa(),
        'comida' => _comida(),
        'agora' => _agora(),
        'fumaca' => _fumaca(p),
        'sombra' => _sombra(),
        'planos' => 'O ThermoGuia é gratuito. Se quiser apoiar, toque em Perfil > Apoie o ThermoGuia: as doações ajudam a '
            'plantar árvores e a entregar máscaras de proteção em Manaus.',
        'por_que_calor' => _porQueCalor(p),
        'umidade' => _umidade(),
        'max_hoje' => _maxHoje(),
        'previsao' => _previsao(p),
        'alagamento' => _alagamento(p),
        'causa_fumaca' => _causaFumaca(),
        'denunciar' => _denunciar(),
        'mascara' => _mascara(p),
        _ => _dica(),
      };

  // ---------- dados ----------

  ClimateSnapshot get now => c.climate;
  String get lvl => c.risk.level.label.toLowerCase();
  int get feels => c.risk.effectiveIndexC.round();
  bool get night => !now.isDay;

  /// Previsão para a [hour] mais próxima a partir de agora (hoje ou amanhã).
  HourlyPoint? forecastAt(int hour, {bool tomorrow = false}) {
    for (final h in c.hourly) {
      if (h.time.hour != hour || h.time.isBefore(now.time.subtract(const Duration(minutes: 59)))) continue;
      if (tomorrow && h.time.day == now.time.day) continue;
      return h;
    }
    return null;
  }

  double _uvAdj(double uv) => uv >= 11 ? 3.0 : uv >= 8 ? 2.0 : uv >= 6 ? 1.0 : 0.0;

  /// Sensação agora, na mesma conta usada para as próximas horas.
  double get feelsNow =>
      heatIndexC(now.temperatureC, now.humidity) + (night ? 0 : _uvAdj(now.uvIndex)) + (c.persona == Persona.idoso ? 1.5 : 0);

  double feelsAt(HourlyPoint h, {double effort = 0}) {
    return heatIndexC(h.temperatureC, h.humidity) + _uvAdj(h.uvIndex) + effort + (c.persona == Persona.idoso ? 1.5 : 0);
  }

  String _when(DateTime t) {
    final today = t.day == now.time.day;
    return '${today ? '' : 'amanhã '}às ${t.hour}h';
  }

  /// "das 17h às 19h".
  String _range(ComfortWindow w) => 'das ${w.start.hour}h às ${w.end.hour}h';

  String get _bestWindow {
    if (c.windows.isEmpty) return '';
    final w = c.windows.first;
    return '${_range(w)} (sensação de ~${w.avgHeatIndexC.round()}°C)';
  }

  /// Horário mais ameno para a atividade (com o esforço dela), se for bem
  /// melhor que o perguntado.
  HourlyPoint? _betterHour(Activity act, double askedFeels, {int? notHour}) {
    final options = c.hourly
        .where((h) => h.time.isAfter(now.time) && h.time.difference(now.time).inHours <= 24)
        .where((h) => h.time.hour >= 6 && h.time.hour <= 21 && h.time.hour != notHour)
        .toList();
    if (options.isEmpty) return null;
    final best = options.reduce((a, b) => feelsAt(a, effort: act.effortC) <= feelsAt(b, effort: act.effortC) ? a : b);
    return feelsAt(best, effort: act.effortC) <= askedFeels - 3 ? best : null;
  }

  // ---------- respostas ----------

  String _atividade(ParsedQuestion p) {
    final act = p.activity ?? Activity.caminhar;
    final atHour = p.hour;
    final tomorrow = p.has(r'amanha');
    final h = atHour == null || (atHour == now.time.hour && !tomorrow) ? null : forecastAt(atHour, tomorrow: tomorrow);
    final whenTxt = h == null ? 'Agora' : _cap(_when(h.time));
    final f = h == null ? c.risk.effectiveIndexC + act.effortC : feelsAt(h, effort: act.effortC);
    final uv = h?.uvIndex ?? now.uvIndex;
    final level = _engine.levelFor(f);

    final dur = p.durationMin ?? (p.distanceKm == null ? null : (p.distanceKm! / act.kmh * 60).round());
    final what = [
      act.label,
      if (p.distanceKm != null) _km(p.distanceKm!),
      if (dur != null) '(~$dur min)',
    ].join(' ');

    final verdict = switch (level) {
      RiskLevel.baixo => 'Sim, pode ir tranquilo.',
      RiskLevel.moderado => 'Sim, dá para ir com cuidados simples.',
      RiskLevel.alto => 'Dá, mas com pausas e água por perto.',
      RiskLevel.muitoAlto => 'Não recomendo.',
      RiskLevel.extremo => 'Não. É perigoso.',
    };
    final water = dur == null ? null : _waterFor(dur, level);
    final better = level.index >= RiskLevel.alto.index ? _betterHour(act, f, notHour: h?.time.hour ?? now.time.hour) : null;
    final tips = <String>[
      if (better != null) 'Melhor ${_when(better.time)} (~${feelsAt(better, effort: act.effortC).round()}°C).',
      if (level.index >= RiskLevel.alto.index && uv >= 6) 'O UV estará em ${uv.round()}: use boné e protetor.',
      if (water != null) 'Leve pelo menos ${_ml(water)} de água.',
      if (act == Activity.pedalar || act == Activity.caminhar) 'Na aba Rotas eu escolho o caminho com mais sombra.',
      if (level.index >= RiskLevel.alto.index) 'Pare se sentir tontura, dor de cabeça ou enjoo.',
    ];
    return '$verdict $whenTxt, para $what, a sensação deve ficar em ~${f.round()}°C '
        '(risco ${level.label.toLowerCase()}). ${tips.join(' ')}';
  }

  int _waterFor(int minutes, RiskLevel level) {
    final perHour = switch (level) {
      RiskLevel.baixo => 300,
      RiskLevel.moderado => 450,
      RiskLevel.alto => 600,
      RiskLevel.muitoAlto => 750,
      RiskLevel.extremo => 900,
    };
    return math.max(200, (minutes / 60 * perHour / 50).round() * 50);
  }

  /// "750 ml", "1,5 litro", "3 litros".
  String _ml(int ml) {
    if (ml < 1000) return '$ml ml';
    final l = ml / 1000;
    final txt = l.toStringAsFixed(l == l.roundToDouble() ? 0 : 1).replaceAll('.', ',');
    return '$txt ${l < 2 ? 'litro' : 'litros'}';
  }

  String _dur(int min) =>
      min >= 60 ? '${(min / 60).toStringAsFixed(min % 60 == 0 ? 0 : 1).replaceAll('.', ',')} h' : '$min min';

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _km(double km) => km >= 1
      ? '${km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1).replaceAll('.', ',')} km'
      : '${(km * 1000).round()} m';

  String _melhorHorario(ParsedQuestion p) {
    if (c.windows.isEmpty) return 'Ainda não tenho a previsão das próximas horas para indicar um horário.';
    final act = p.activity;
    final list = c.windows.take(3).map((w) => '${_range(w)} (~${w.avgHeatIndexC.round()}°C)').join('; ');
    return 'Os melhores horários${act == null ? '' : ' para ${act.label}'} nas próximas 24h são: $list.'
        '${c.avoid != null ? ' Evite sair ${_range(c.avoid!)}, o período mais quente.' : ''}';
  }

  String _maisQuente() {
    if (c.hourly.isEmpty) return 'Ainda não tenho a previsão das próximas horas.';
    final next = c.hourly.where((h) => h.time.day == now.time.day && h.time.hour >= now.time.hour).toList();
    final pool = next.isEmpty ? c.hourly.take(12).toList() : next;
    final peak = pool.reduce((a, b) => feelsAt(a) >= feelsAt(b) ? a : b);
    return 'O pico de calor ${peak.time.day == now.time.day ? 'hoje' : 'amanhã'} deve ser às ${peak.time.hour}h, '
        'com sensação de ~${feelsAt(peak).round()}°C e UV ${peak.uvIndex.round()}.'
        '${c.avoid != null ? ' Evite ficar ao sol ${_range(c.avoid!)}.' : ''}';
  }

  String _agoraVsDepois() {
    final later = c.hourly.where((h) => h.time.isAfter(now.time) && h.time.difference(now.time).inHours <= 12).toList();
    if (later.isEmpty) return _agora();
    final coolest = later.reduce((a, b) => feelsAt(a) <= feelsAt(b) ? a : b);
    final diff = feelsAt(coolest) - feelsNow;
    final peak = later.where((h) => h.time.isBefore(coolest.time)).fold<HourlyPoint?>(
        null, (m, h) => m == null || feelsAt(h) > feelsAt(m) ? h : m);
    final hotterFirst = peak != null && feelsAt(peak) > feelsNow + 2;
    if (diff <= -1.5) {
      return 'Sim. Refresca ${_when(coolest.time)} (~${feelsAt(coolest).round()}°C de sensação; agora está em ~${feelsNow.round()}°C).'
          '${hotterFirst ? ' Antes disso ainda esquenta: o pico é ${_when(peak.time)} (~${feelsAt(peak).round()}°C).' : ''}';
    }
    return 'Não muito nas próximas 12h: a sensação fica perto de ~${feelsNow.round()}°C. '
        'Se precisar sair, vá pela sombra e com água.';
  }

  String _agua(ParsedQuestion p) {
    final missing = (c.risk.waterGoalMl - c.waterMl).clamp(0, 10000);
    final today = 'Sua meta hoje é ${_ml(c.risk.waterGoalMl)}: você já tomou ${_ml(c.waterMl)}'
        '${missing > 0 ? ' e faltam cerca de ${_ml(missing)}' : ' e bateu a meta'}.';
    final rhythm = 'Com risco $lvl, beba um copo a cada ${c.risk.hydrationIntervalMin} min na rua, mesmo sem sede.';
    if (p.durationMin != null) {
      return 'Para ${_dur(p.durationMin!)} na rua, leve cerca de ${_ml(_waterFor(p.durationMin!, c.risk.level))} de água. '
          '$rhythm $today';
    }
    return 'Beba um copo (200 ml) agora. $today $rhythm';
  }

  String _refresco() => c.nearbyOases.isEmpty
      ? 'Não encontrei pontos de refresco mapeados perto de você. Shoppings, farmácias e supermercados costumam ter '
          'ar-condicionado e água. Se conhecer um lugar bom, marque no mapa da aba Rotas (toque e segure).'
      : 'Perto de você: ${c.nearbyOases.join('; ')}. No mapa da aba Rotas eles aparecem como gotas azuis.';

  String _roupa() {
    final rain = c.hourly.take(6).fold<double>(now.precipitationProb, (m, h) => math.max(m, h.precipitationProb));
    if (night) {
      return 'Roupa leve e confortável basta: o sol já não pesa. ${rain >= 40 ? 'Leve uma capa fina, há ${rain.round()}% de chance de chuva. ' : ''}'
          'Se for a lugares com ar-condicionado forte, um casaco fino ajuda.';
    }
    return [
      'Roupas leves, largas e de cor clara (algodão ou tecido dry-fit).',
      if (now.uvIndex >= 3) 'Boné ou chapéu de aba larga e óculos escuros (UV ${now.uvIndex.round()} agora).',
      if (now.uvIndex >= 3) 'Protetor solar FPS 30 ou mais no rosto, pescoço e braços.',
      if (rain >= 40) 'Leve uma capa ou guarda-chuva: ${rain.round()}% de chance de chuva nas próximas horas.',
      if (c.risk.level.index >= RiskLevel.alto.index) 'Evite roupas escuras e tecidos grossos; uma toalhinha úmida no pescoço ajuda.',
    ].join(' ');
  }

  String _chuva() {
    final next = c.hourly.where((h) => h.time.isAfter(now.time)).take(12).toList();
    if (next.isEmpty) return 'Chance de chuva agora: ${now.precipitationProb.round()}%.';
    final wet = next.where((h) => h.precipitationProb >= 40).toList();
    final peak = next.reduce((a, b) => a.precipitationProb >= b.precipitationProb ? a : b);
    if (wet.isEmpty) {
      return 'Chuva pouco provável nas próximas 12h (no máximo ${peak.precipitationProb.round()}%). '
          '${now.isDay && now.uvIndex >= 6 ? 'Um guarda-chuva ainda serve como sombra contra o sol forte.' : 'Pode deixar o guarda-chuva em casa.'}';
    }
    return 'Sim, leve guarda-chuva: a chance de chuva chega a ${peak.precipitationProb.round()}% ${_when(peak.time)}'
        '${wet.first.time != peak.time ? ' e passa de 40% a partir das ${wet.first.time.hour}h' : ''}. '
        'Depois da chuva o ar fica mais úmido e a sensação de calor pode subir.';
  }

  String _sol(ParsedQuestion p) {
    if (night) return 'O sol já se pôs, então não há risco de queimadura agora. Amanhã, o UV costuma ser mais fraco antes das 9h e depois das 16h.';
    final uv = now.uvIndex;
    final burn = uv >= 8 ? '15 minutos' : uv >= 6 ? '25 minutos' : uv >= 3 ? '45 minutos' : null;
    final weaker = c.hourly
        .where((h) => h.time.isAfter(now.time) && h.time.day == now.time.day && h.uvIndex < 3)
        .map((h) => h.time.hour)
        .firstOrNull;
    if (p.has(r'quanto tempo') && burn != null) {
      return 'Cerca de $burn, se a pele for clara e estiver sem protetor (UV ${uv.round()} agora). '
          'Com protetor FPS 30+ dá para ficar mais, reaplicando a cada 2h ou depois de suar.'
          '${weaker != null ? ' A partir das ${weaker}h o sol fica mais fraco.' : ''}';
    }
    // "Que horas o sol fica mais fraco?" → o horário vem primeiro.
    if (p.has(r'que horas|quando|a partir de que')) {
      return weaker == null
          ? 'Hoje o UV fica alto até o fim da tarde; antes das 9h e depois das 16h costuma ser mais seguro.'
          : 'O sol fica mais fraco a partir das ${weaker}h (UV abaixo de 3). Até lá, o UV chega a ${uv.round()}: '
              'use protetor, boné e prefira a sombra.';
    }
    return 'UV agora: ${uv.round()} (${uv >= 8 ? 'muito alto' : uv >= 6 ? 'alto' : uv >= 3 ? 'moderado' : 'baixo'}). '
        '${burn == null ? 'Baixo risco de queimadura.' : 'Pele clara pode queimar em ~$burn sem proteção: use protetor FPS 30+ e reaplique a cada 2h ou depois de suar.'}'
        '${weaker != null && uv >= 3 ? ' O sol fica mais fraco a partir das ${weaker}h.' : ''}';
  }

  String _pet() {
    final asphalt = now.temperatureC + (night ? 2 : now.uvIndex >= 6 ? 22 : now.uvIndex >= 3 ? 14 : 6);
    final best = c.windows.isEmpty ? 'cedo ou depois do pôr do sol' : _range(c.windows.first);
    if (asphalt >= 48) {
      return 'Agora não. O asfalto deve estar perto de ${asphalt.round()}°C e pode queimar as patas em poucos minutos. '
          'Teste: encoste a mão no chão por 5 segundos; se não aguentar, ele também não aguenta. '
          'Melhor passeio: $best, por gramado ou sombra, com água para ele.';
    }
    return 'Pode, com cuidado: o chão deve estar em ~${asphalt.round()}°C. Prefira grama e sombra, leve água para ele '
        'e faça pausas. Cães de focinho curto e idosos sofrem mais com o calor.';
  }

  String _kit(ParsedQuestion p) {
    final dur = p.durationMin ?? 60;
    final water = _waterFor(dur, c.risk.level);
    return [
      'Para ${_dur(dur)} na rua, leve:',
      '• ${_ml(water)} de água (garrafa térmica ajuda);',
      if (!night) '• boné ou chapéu, óculos escuros e protetor solar;',
      '• uma toalhinha para molhar e pôr no pescoço;',
      if (dur >= 90) '• uma fruta ou lanche salgado para repor sais;',
      if (c.hourly.take(6).any((h) => h.precipitationProb >= 40)) '• capa ou guarda-chuva (chance de chuva);',
      '• celular carregado, para usar as Rotas Frescas e o botão "Estou passando mal".',
    ].join('\n');
  }

  String _sinais() => 'Sinais de exaustão pelo calor: suor excessivo, cansaço, tontura, dor de cabeça, enjoo, câimbras e pele fria e úmida. '
      'Nesses casos, pare na sombra, beba água aos poucos e refresque o corpo.\n\n'
      'Insolação é mais grave: pele quente e seca, confusão, fala enrolada, desmaio ou temperatura muito alta. '
      'Ligue 192 (SAMU) na hora e use o botão "Estou passando mal" do app.';

  String _emergencia() => 'Pare agora em um lugar com sombra ou ar-condicionado, sente-se, afrouxe a roupa e beba água em pequenos goles. '
      'Molhe o rosto, a nuca e os pulsos. Se houver confusão, desmaio, vômito ou a pele estiver quente e seca, '
      'ligue 192 (SAMU) imediatamente. Use o botão "Estou passando mal" para avisar seus contatos.';

  String _vulneravel(ParsedQuestion p) {
    final baby = p.has(r'bebe|recem');
    final elder = p.has(r'idos|avo\b|vovo');
    final preg = p.has(r'gestante|gravida');
    return [
      if (baby) 'Bebês não devem ficar ao sol direto. Ofereça o peito ou água (se já toma) com frequência e use roupas leves.',
      if (elder) 'Idosos sentem menos sede: ofereça água a cada 30 min, mesmo sem pedir, e evite saídas ${c.avoid == null ? 'das 11h às 16h' : _range(c.avoid!)}.',
      if (preg) 'Gestantes desidratam mais rápido: água sempre por perto, pausas na sombra e atenção a tontura.',
      if (!baby && !elder && !preg) 'Crianças esquentam mais rápido que adultos: água a cada 20 min, boné, protetor e brincadeiras na sombra.',
      'Hoje o risco está $lvl. ${_bestWindow.isEmpty ? '' : 'Para sair juntos, o melhor horário é $_bestWindow.'}',
      'Nunca deixe ninguém dentro de carro fechado, nem por poucos minutos.',
    ].join(' ');
  }

  String _exposicao() {
    final m = c.exposureMin;
    if (m == 0) {
      return 'Hoje ainda não registrei tempo seu ao sol. Quando sair, ligue "Estou na rua agora" na tela inicial para eu acompanhar.';
    }
    return 'Você já passou cerca de $m min ao sol hoje. '
        '${m >= 120 ? 'É bastante: prefira lugares com sombra pelo resto do dia e reforce a água.' : m >= 60 ? 'Faça pausas na sombra e mantenha a água em dia.' : 'Ainda está tranquilo, siga com água e sombra.'}';
  }

  String _casa() => 'Para refrescar a casa: feche janelas e cortinas do lado do sol durante o dia e abra tudo à noite para o ar circular. '
      'Um pano úmido ou uma vasilha com gelo na frente do ventilador ajuda. Tome um banho morno antes de dormir, '
      'use lençol de algodão e deixe uma garrafa de água ao lado da cama.';

  String _comida() => 'No calor, prefira refeições leves: frutas com muita água (melancia, laranja, abacaxi, cupuaçu), saladas e sopas frias. '
      'Água de coco repõe sais. Evite álcool, excesso de café, energéticos e refrigerantes, que desidratam, '
      'e refeições pesadas antes de sair no sol.';

  String _agora() {
    final top = c.risk.recommendations.isEmpty ? '' : ' ${c.risk.recommendations.first.message}';
    final a = c.airNow;
    final air = a == null
        ? ''
        : ' Qualidade do ar ${a.level.label.toLowerCase()}${a.level.isBad ? ' por causa da fumaça: use máscara de proteção na rua' : ''}.';
    return 'Agora em ${c.city.name}: ${now.temperatureC.round()}°C, umidade ${now.humidity.round()}%'
        '${night ? '' : ', UV ${now.uvIndex.round()}'}. Para você a sensação é de ~$feels°C, risco $lvl.$air$top';
  }

  String _saudacao() {
    final name = c.userName.isEmpty ? '' : ', ${c.userName.split(' ').first}';
    return 'Oi$name! ${_today().join(' ')}';
  }

  String _dica() {
    final recs = c.risk.recommendations.take(2).map((r) => r.message).join(' ');
    return 'Minha dica para agora (risco $lvl, sensação de ~$feels°C): ${recs.isEmpty ? 'mantenha a água em dia e prefira a sombra.' : recs}'
        '${_bestWindow.isEmpty ? '' : ' Se puder escolher, saia $_bestWindow.'}';
  }

  String _fumaca(ParsedQuestion p) {
    final a = c.airNow;
    if (a == null) {
      return 'Agora não consegui a medição da fumaça. Com cheiro de queimado no ar, use máscara de proteção na rua, '
          'evite esforço e mantenha as janelas fechadas.';
    }
    final advice = c.airAdvice!;
    final cig = cigarettesFor(a.pm25);
    final safe = c.safeWindows;
    DateTime? clears;
    if (a.level.isBad) {
      for (final h in c.airHourly) {
        if (h.time.isAfter(now.time) && !h.level.isBad) {
          clears = h.time;
          break;
        }
      }
    }
    final askingWhen = p.has(r'que horas?|quando|horario|ate que|a partir de|sem fumaca|ar limpo|ar bom');
    final parts = <String>[
      if (askingWhen)
        a.level.isBad
            ? (clears != null
                ? 'O ar deve ficar sem fumaça forte ${_when(clears)}.'
                : 'Não há previsão de o ar ficar sem fumaça nas próximas horas.')
            : 'Agora o ar já está sem fumaça forte.',
      'A qualidade do ar está ${a.level.label.toLowerCase()} agora (índice ${a.index}). '
          '${cig >= 0.5 ? 'Respirar esse ar o dia todo equivale a ${cig.toStringAsFixed(1).replaceAll('.', ',')} cigarros. ' : ''}'
          '${advice.message}',
      if (!askingWhen && a.level.isBad && clears != null) 'A previsão é de melhora ${_when(clears)}.',
      if (!askingWhen && a.level.isBad && clears == null) 'Não há previsão de melhora nas próximas horas.',
      if (safe.isNotEmpty) 'Hora Segura para sair: ${safe.map((w) => w.rangeLabel).join(' e ')}.',
      if (p.has(r'casa|janela|dormir|quarto'))
        'Em casa: janelas fechadas enquanto o ar estiver ruim, pano úmido nas frestas e ventilador ligado. Abra tudo quando o app avisar que o ar melhorou.',
      if (p.has(r'asma|bronquite|rinite|alergi|doenca respiratoria|pulmao|\bdpoc\b'))
        'Quem tem asma ou bronquite sente primeiro: deixe a bombinha por perto, evite sair nos horários de ar ruim e procure atendimento se a falta de ar não passar.',
      if (p.has(r'crianca|bebe|filho|filha|idos|avo\b|vovo|gestante|gravida'))
        'Crianças, idosos e gestantes respiram mais rápido e sofrem mais com a fumaça: em dia de ar ruim, brincadeiras e passeios dentro de casa.',
      if (a.level.isBad && (p.activity != null || p.has(r'exercici|treino|esporte|academia')))
        'Com o ar assim, evite exercício ao ar livre: no esforço você respira muito mais fumaça. Prefira lugares fechados.',
      if (p.has(r'chuv'))
        'A chuva ajuda a baixar a fumaça e o ar costuma melhorar depois de um bom temporal. Agora a chance de chuva é de ${now.precipitationProb.round()}%.',
    ];
    return parts.join(' ');
  }

  String _sombra() {
    final a = c.airNow;
    final smoke = a != null && a.level.isBad;
    return 'A sombra das árvores deixa a calçada até 10 °C mais fresca e é o que as Rotas Frescas procuram: '
        'abra a aba Rotas e eu escolho o caminho mais sombreado para o horário em que você vai passar. '
        '${smoke ? 'Atenção: hoje a fumaça cobre a cidade inteira e a sombra não filtra o ar. Use máscara de proteção mesmo nas ruas arborizadas.' : 'Nas horas de sol forte, ande pelo lado da rua com sombra.'}';
  }

  /// Sem assunto reconhecido: em vez de dizer que não entendeu, conta o que
  /// importa agora sobre o calor e a fumaça e oferece os próximos passos.
  String _fallback() =>
      ['Eu acompanho o calor e a fumaça em ${c.city.name}, então aqui vai o que importa agora:', ..._today()].join(' ');

  /// Resumo de agora: calor, fumaça, chuva ou temporal e sol, e o que perguntar.
  List<String> _today() {
    final a = c.airNow;
    final safe = c.safeWindows;
    final rain = forecastAlerts(c.hourly, now: now.time, hours: 12).where((x) => x.kind.isRain).firstOrNull;
    final sun = !night && now.uvIndex >= 6;
    return [
      'Calor: ${now.temperatureC.round()}°C com sensação de ~$feels°C para você (risco $lvl).',
      if (a != null)
        'Fumaça: a qualidade do ar está ${a.level.label.toLowerCase()}'
            '${a.level.isBad ? '; use máscara de proteção na rua' : ''}'
            '${safe.isNotEmpty ? '. Hora Segura para sair: ${safe.first.rangeLabel}' : ''}.',
      rain != null ? 'Chuva: ${rain.message}' : 'Chuva: sem previsão de chuva forte nas próximas horas.',
      if (sun) 'Sol: UV ${now.uvIndex.round()} agora; use protetor, boné e prefira a sombra.',
      'Pode me perguntar o melhor horário para sair, se precisa de máscara ou se vai chover.',
    ];
  }

  // ---------- calor em Manaus, previsão e fumaça ----------

  String _porQueCalor(ParsedQuestion p) {
    final city = 'Manaus fica perto da linha do Equador: o sol chega quase a pino o ano todo, e a umidade da floresta e dos rios '
        'deixa o ar abafado, o que dificulta o suor evaporar e aumenta a sensação de calor.';
    final island = 'Na cidade, asfalto, concreto e telhados guardam o calor do dia (a ilha de calor urbana): áreas com muito '
        'asfalto e pouca árvore esquentam vários graus a mais que bairros arborizados e parques, e demoram mais para esfriar à noite.';
    final nowTxt = 'Agora: ${now.temperatureC.round()}°C e umidade de ${now.humidity.round()}%, sensação de ~$feels°C.';
    final tip = 'Por isso as Rotas Frescas buscam ruas com sombra de árvores.';
    return p.has(r'ilha|bairro|esquentam') ? '$island $city $nowTxt $tip' : '$city $island $nowTxt';
  }

  String _umidade() {
    final h = now.humidity.round();
    final gap = feels - now.temperatureC.round();
    return h >= 60
        ? 'Sim. Com umidade de $h% agora, o suor evapora pouco e o corpo se resfria menos: por isso a sensação '
            '(~$feels°C) fica ${gap > 0 ? '$gap graus ' : ''}acima dos ${now.temperatureC.round()}°C do termômetro. '
            'Roupas leves e largas, sombra e água ajudam o corpo a perder calor.'
        : 'A umidade está em $h% agora, mais baixa que o normal em Manaus. O suor evapora rápido e você perde água sem perceber: '
            'beba mesmo sem sede${c.airNow != null && c.airNow!.level.isBad ? ', e com o ar seco a fumaça irrita mais olhos e garganta' : ''}.';
  }

  String _maxHoje() {
    final today = c.hourly.where((h) => h.time.day == now.time.day).toList();
    if (today.isEmpty) return 'Ainda não tenho a previsão de hoje.';
    final max = today.reduce((a, b) => a.temperatureC >= b.temperatureC ? a : b);
    final min = today.reduce((a, b) => a.temperatureC <= b.temperatureC ? a : b);
    final passed = max.time.hour < now.time.hour;
    return 'Hoje a máxima ${passed ? 'já foi' : 'prevista é'} de ~${max.temperatureC.round()}°C por volta das ${max.time.hour}h '
        '(sensação de ~${feelsAt(max).round()}°C), e a mais baixa das próximas horas fica em ~${min.temperatureC.round()}°C às ${min.time.hour}h.'
        '${c.avoid != null ? ' Evite o sol ${_range(c.avoid!)}.' : ''}';
  }

  String _previsao(ParsedQuestion p) {
    final tomorrow = p.has(r'amanha');
    final day = c.hourly.where((h) => tomorrow ? h.time.day != now.time.day : h.time.day == now.time.day && !h.time.isBefore(now.time)).toList();
    if (day.isEmpty) return 'Ainda não tenho a previsão ${tomorrow ? 'de amanhã' : 'das próximas horas'}. Tente de novo mais tarde.';
    final hottest = day.reduce((a, b) => feelsAt(a) >= feelsAt(b) ? a : b);
    final wettest = day.reduce((a, b) => a.precipitationProb >= b.precipitationProb ? a : b);
    // Só os avisos de chuva: a sensação de calor já vem na primeira frase.
    final alerts = forecastAlerts(day, now: day.first.time, hours: 24).where((a) => a.kind.isRain).toList();
    final smoke = c.airHourly.where((h) => day.any((d) => d.time.hour == h.time.hour && d.time.day == h.time.day)).any((h) => h.level.isBad);
    return [
      '${tomorrow ? 'Amanhã' : 'No resto do dia'}: máxima de ~${hottest.temperatureC.round()}°C por volta das ${hottest.time.hour}h '
          '(sensação de até ~${feelsAt(hottest).round()}°C) e chance de chuva de até ${wettest.precipitationProb.round()}%'
          '${wettest.precipitationProb >= 30 ? ' às ${wettest.time.hour}h' : ''}.',
      if (alerts.isNotEmpty) '${alerts.first.title}: ${alerts.first.message}',
      if (smoke) 'A fumaça deve continuar: tenha a máscara de proteção por perto.',
      if (p.has(r'proximos dias|semana')) 'Por enquanto tenho a previsão hora a hora só até amanhã.',
    ].join(' ');
  }

  String _alagamento(ParsedQuestion p) {
    final rain = forecastAlerts(c.hourly, now: now.time, hours: 24).where((a) => a.kind.isRain).firstOrNull;
    final next = c.hourly.where((h) => h.time.isAfter(now.time)).take(24).toList();
    final maxProb = next.isEmpty ? now.precipitationProb : next.map((h) => h.precipitationProb).reduce(math.max);
    final tips = 'Em dia de temporal: não atravesse ruas alagadas (a correnteza arrasta e a água pode esconder buracos), '
        'fique longe da beira dos igarapés e de encostas, e tire os aparelhos da tomada se a água entrar em casa. '
        'Defesa Civil: 199; Bombeiros: 193.';
    if (rain == null) {
      return 'Sem previsão de chuva forte nas próximas 24 horas (no máximo ${maxProb.round()}% de chance de chuva), '
          'então o risco de alagamento é baixo. ${p.has(r'o que (eu )?(faco|fazer)|como (me )?proteger') ? tips : ''}'.trim();
    }
    return switch (rain.kind) {
      WeatherAlertKind.alagamento => rain.message,
      WeatherAlertKind.chuva => '${rain.message} Não há previsão de chuva forte, então o risco de alagamento é baixo.',
      _ => '${rain.message} Com chuva forte, ruas baixas podem alagar. $tips',
    };
  }

  String _causaFumaca() {
    final a = c.airNow;
    return 'A fumaça vem das queimadas na Amazônia, principalmente no sul do Amazonas e em estados vizinhos, além de focos '
        'perto de Manaus. Na seca, mais forte entre agosto e novembro, a vegetação fica seca, o fogo se espalha fácil e o vento '
        'traz a fumaça para a cidade. Em anos de seca severa, como 2023 e 2024, ela cobriu Manaus por semanas. '
        'O ar costuma melhorar com a volta das chuvas. '
        '${a == null ? '' : 'Agora a qualidade do ar está ${a.level.label.toLowerCase()} (índice ${a.index}).'}'.trim();
  }

  String _denunciar() => 'Se o fogo estiver perto de casas, pessoas ou mata, ligue 193 (Bombeiros). Para denunciar queimada '
      'ilegal, ligue para a Linha Verde do Ibama: 0800 061 8080 (ligação grátis). Diga o local exato e, se puder, mande foto. '
      'Não tente apagar um fogo grande sozinho e fique longe da fumaça.';

  String _mascara(ParsedQuestion p) {
    final a = c.airNow;
    return [
      'A que protege da fumaça é a máscara de proteção que veda bem no rosto, com elástico atrás da cabeça e clipe no nariz '
          '(vendida em farmácias e lojas de material de construção). Máscara de pano ou cirúrgica quase não segura a fumaça fina.',
      'Ajuste bem, sem folga nas laterais, e troque quando ficar suja, úmida ou difícil de respirar.',
      if (p.has(r'purificador|dentro de casa|em casa'))
        'Dentro de casa, um purificador de ar com filtro HEPA ajuda, com portas e janelas fechadas.',
      if (a != null)
        a.level.isBad
            ? 'Hoje precisa: a qualidade do ar está ${a.level.label.toLowerCase()}.'
            : 'Agora o ar está ${a.level.label.toLowerCase()}, então não precisa na rua.',
    ].join(' ');
  }
}
