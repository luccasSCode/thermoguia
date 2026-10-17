import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'claude_service.dart';

/// Categorias da Comunidade e o que a foto precisa mostrar.
class PostCategory {
  const PostCategory(this.id, this.label, this.badge, this.evidence);
  final String id;
  final String label;

  /// Nome do selo da semana.
  final String badge;

  /// O que a IA deve ver para considerar comprovado.
  final String evidence;
}

const postCategories = [
  PostCategory('agua', 'Hidratação', '+ Hidratado',
      'a mesma garrafa ou copo fotografado antes e depois, com o nível de água mais baixo na segunda foto'),
  PostCategory('bone', 'Boné ou chapéu', '+ Usou boné',
      'uma pessoa com boné ou chapéu na cabeça (não basta o boné na mão, na mesa ou pendurado)'),
  PostCategory('protetor', 'Protetor solar', '+ Usou protetor solar',
      'protetor solar sendo aplicado na pele, ou o frasco junto de pele com o creme visível '
          '(só o frasco, sem sinal de aplicação, não comprova)'),
  PostCategory('guarda_sol', 'Guarda-sol', '+ Usou guarda-sol',
      'uma pessoa segurando um guarda-sol ou guarda-chuva aberto para se proteger do sol, ao ar livre'),
  PostCategory('oculos', 'Óculos de sol', '+ Usou óculos de sol', 'uma pessoa usando óculos de sol no rosto'),
];

PostCategory? categoryById(String id) => postCategories.where((c) => c.id == id).firstOrNull;

/// Resultado de uma verificação: o que fazer com o post e por quê.
class Decision {
  const Decision(this.status, this.reason, {this.ml});

  /// aprovado, revisao (vai para a equipe) ou recusado.
  final String status;
  final String reason;
  final int? ml;

  bool get approved => status == 'aprovado';
}

/// Verificação das fotos. A IA descreve o que vê em um formato fixo; quem
/// decide são as regras abaixo, que só aprovam com confiança alta. Na
/// dúvida, o caso vai para revisão humana: um erro nunca dá gotas ou selos
/// a quem não fez a tarefa.
class VerificationService {
  VerificationService(this._claude);
  final ClaudeService _claude;

  static const _system = '''
Você verifica fotos do ThermoGuia, um app de proteção contra o calor em Manaus.
Pessoas enviam fotos para comprovar hábitos (beber água, usar boné, protetor solar,
guarda-sol, óculos de sol) e ganham pontos trocados por descontos. Por isso há
incentivo para fraudar: seja rigoroso e descreva apenas o que está visível.

- Marque foto de tela ou impressa quando a imagem for uma foto de outra tela
  (moiré, bordas de monitor, reflexo de vidro, interface de app) ou de papel.
- Marque montagem quando houver sinais de edição, colagem, imagem gerada por IA
  ou foto profissional/de banco de imagens.
- conteudo_seguro = false para nudez, violência, ódio, armas, drogas ou dados
  pessoais expostos (documentos, cartões, placas legíveis).
- Use confiança "alta" só quando não houver dúvida razoável. Imagem escura,
  borrada, cortada ou ambígua não é "alta".
- O motivo é lido pela pessoa: português do Brasil, uma frase curta e gentil.
''';

  static const _confidence = {
    'type': 'string',
    'enum': ['alta', 'media', 'baixa'],
  };

  static final postSchema = <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'conteudo_seguro',
      'foto_de_tela_ou_impressa',
      'montagem_ou_internet',
      'comprova_categoria',
      'confianca',
      'descricao',
      'motivo',
    ],
    'properties': {
      'conteudo_seguro': {'type': 'boolean'},
      'foto_de_tela_ou_impressa': {'type': 'boolean'},
      'montagem_ou_internet': {'type': 'boolean'},
      'comprova_categoria': {'type': 'boolean'},
      'confianca': _confidence,
      'descricao': {'type': 'string'},
      'motivo': {'type': 'string'},
    },
  };

  static final waterSchema = <String, dynamic>{
    'type': 'object',
    'additionalProperties': false,
    'required': [
      'conteudo_seguro',
      'foto_de_tela_ou_impressa',
      'montagem_ou_internet',
      'mesmo_recipiente',
      'confianca_mesmo_recipiente',
      'tipo_recipiente',
      'capacidade_ml',
      'origem_capacidade',
      'nivel_antes_pct',
      'nivel_depois_pct',
      'confianca_niveis',
      'descricao',
      'motivo',
    ],
    'properties': {
      'conteudo_seguro': {'type': 'boolean'},
      'foto_de_tela_ou_impressa': {'type': 'boolean'},
      'montagem_ou_internet': {'type': 'boolean'},
      'mesmo_recipiente': {'type': 'boolean'},
      'confianca_mesmo_recipiente': _confidence,
      'tipo_recipiente': {'type': 'string'},
      'capacidade_ml': {'type': 'integer'},
      'origem_capacidade': {
        'type': 'string',
        'enum': ['rotulo', 'graduacao', 'formato_conhecido', 'incerta'],
      },
      'nivel_antes_pct': {'type': 'integer'},
      'nivel_depois_pct': {'type': 'integer'},
      'confianca_niveis': _confidence,
      'descricao': {'type': 'string'},
      'motivo': {'type': 'string'},
    },
  };

  bool get aiEnabled => _claude.enabled;

  /// Devolve (decisão, resposta da IA para auditoria).
  Future<(Decision, Map<String, dynamic>?)> verifyPost(PostCategory c, List<int> photo, String mime) async {
    final ai = await _claude.analyzeImages(
      system: _system,
      images: [(photo, mime)],
      instruction: 'Categoria declarada: ${c.label}.\n'
          'Para comprovar, a foto precisa mostrar: ${c.evidence}.\n'
          'Preencha o formato pedido.',
      schema: postSchema,
    );
    return (ai == null ? pendingReview : decidePost(ai), ai);
  }

  Future<(Decision, Map<String, dynamic>?)> verifyWater(
    List<int> before,
    List<int> after,
    String mime, {
    required Duration elapsed,
  }) async {
    final ai = await _claude.analyzeImages(
      system: _system,
      images: [(before, mime), (after, mime)],
      instruction: 'Prova de hidratação. A primeira foto é o recipiente ANTES de beber e a segunda, '
          '${elapsed.inMinutes} minutos depois.\n'
          '- Diga se é o MESMO recipiente (formato, cor, rótulo, tampa, marcas).\n'
          '- Capacidade em ml: leia do rótulo ou das marcações de volume. Use "formato_conhecido" só '
          'para embalagens padrão inconfundíveis; se não der para saber, use "incerta" e 0.\n'
          '- Nível de água em % da capacidade em cada foto (0 = vazio, 100 = cheio).\n'
          'Preencha o formato pedido.',
      schema: waterSchema,
    );
    return (ai == null ? pendingReview : decideWater(ai), ai);
  }

  static const pendingReview = Decision('revisao', 'Sua foto está na fila de revisão da equipe.');

  /// Regras para boné, protetor, guarda-sol e óculos.
  static Decision decidePost(Map<String, dynamic> ai) {
    final motivo = '${ai['motivo'] ?? ''}'.trim();
    if (ai['conteudo_seguro'] != true) {
      return const Decision('recusado', 'Esta foto não segue as regras da Comunidade.');
    }
    if (ai['foto_de_tela_ou_impressa'] == true) {
      return const Decision('recusado', 'Parece foto de uma tela ou de papel. Tire a foto na hora, com a câmera.');
    }
    if (ai['montagem_ou_internet'] == true) {
      return const Decision('recusado', 'A foto parece editada ou tirada da internet.');
    }
    if (ai['comprova_categoria'] != true || ai['confianca'] == 'baixa') {
      return Decision('recusado', motivo.isEmpty ? 'A foto não mostra o cuidado escolhido.' : motivo);
    }
    if (ai['confianca'] == 'alta') return Decision('aprovado', motivo.isEmpty ? 'Comprovado!' : motivo);
    return const Decision('revisao', 'Não deu para confirmar só pela foto. A equipe vai revisar.');
  }

  /// Regras da água: só aprova com o mesmo recipiente, capacidade lida no
  /// rótulo ou na graduação e níveis com confiança alta. Arredonda para
  /// baixo (múltiplos de 50 ml): na dúvida, conta menos.
  static Decision decideWater(Map<String, dynamic> ai) {
    final motivo = '${ai['motivo'] ?? ''}'.trim();
    if (ai['conteudo_seguro'] != true) {
      return const Decision('recusado', 'Esta foto não segue as regras da Comunidade.');
    }
    if (ai['foto_de_tela_ou_impressa'] == true || ai['montagem_ou_internet'] == true) {
      return const Decision('recusado', 'As fotos precisam ser tiradas na hora, com a câmera do app.');
    }
    if (ai['mesmo_recipiente'] != true || ai['confianca_mesmo_recipiente'] == 'baixa') {
      return const Decision('recusado', 'As duas fotos não parecem ser do mesmo recipiente.');
    }
    final capacity = (ai['capacidade_ml'] as num?)?.toInt() ?? 0;
    final before = ((ai['nivel_antes_pct'] as num?)?.toInt() ?? 0).clamp(0, 100);
    final after = ((ai['nivel_depois_pct'] as num?)?.toInt() ?? 0).clamp(0, 100);
    if (after >= before) return const Decision('recusado', 'O nível de água não baixou entre as duas fotos.');
    if (capacity <= 0 || capacity > 5000 || ai['origem_capacidade'] == 'incerta') {
      return const Decision('revisao', 'Não deu para ler a capacidade do recipiente. A equipe vai revisar.');
    }
    final ml = (capacity * (before - after) / 100 / 50).floor() * 50;
    if (ml < 100) return const Decision('recusado', 'A quantidade foi pequena demais para contar (menos de 100 ml).');

    final sure = ai['confianca_mesmo_recipiente'] == 'alta' &&
        ai['confianca_niveis'] == 'alta' &&
        (ai['origem_capacidade'] == 'rotulo' || ai['origem_capacidade'] == 'graduacao');
    if (!sure) {
      return Decision('revisao', 'A equipe vai confirmar a quantidade (estimativa: $ml ml).', ml: ml);
    }
    return Decision('aprovado', motivo.isEmpty ? '$ml ml comprovados.' : motivo, ml: ml);
  }
}

/// Hash perceptual (dHash 64 bits): fotos iguais ou quase iguais (mesma foto
/// reenviada, recortada ou recomprimida) dão hashes a poucos bits de distância.
int dHash(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('Imagem inválida.');
  final small = img.copyResize(img.grayscale(decoded), width: 9, height: 8, interpolation: img.Interpolation.average);
  var hash = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      hash = (hash << 1) | (small.getPixel(x, y).r < small.getPixel(x + 1, y).r ? 1 : 0);
    }
  }
  return hash;
}

int hammingDistance(int a, int b) {
  var x = a ^ b;
  var n = 0;
  while (x != 0) {
    x &= x - 1;
    n++;
  }
  return n;
}
