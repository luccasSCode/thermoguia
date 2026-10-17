import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:test/test.dart';
import 'package:thermoguia_backend/services/verification_service.dart';

Map<String, dynamic> _post({
  bool safe = true,
  bool screen = false,
  bool fake = false,
  bool proves = true,
  String conf = 'alta',
}) =>
    {
      'conteudo_seguro': safe,
      'foto_de_tela_ou_impressa': screen,
      'montagem_ou_internet': fake,
      'comprova_categoria': proves,
      'confianca': conf,
      'descricao': '',
      'motivo': '',
    };

Map<String, dynamic> _water({
  bool same = true,
  String sameConf = 'alta',
  int capacity = 500,
  String source = 'rotulo',
  int before = 100,
  int after = 40,
  String levels = 'alta',
  bool screen = false,
}) =>
    {
      'conteudo_seguro': true,
      'foto_de_tela_ou_impressa': screen,
      'montagem_ou_internet': false,
      'mesmo_recipiente': same,
      'confianca_mesmo_recipiente': sameConf,
      'tipo_recipiente': 'garrafa',
      'capacidade_ml': capacity,
      'origem_capacidade': source,
      'nivel_antes_pct': before,
      'nivel_depois_pct': after,
      'confianca_niveis': levels,
      'descricao': '',
      'motivo': '',
    };

void main() {
  group('posts (boné, protetor, guarda-sol, óculos)', () {
    test('só aprova com confiança alta', () {
      expect(VerificationService.decidePost(_post()).status, 'aprovado');
      expect(VerificationService.decidePost(_post(conf: 'media')).status, 'revisao');
      expect(VerificationService.decidePost(_post(conf: 'baixa')).status, 'recusado');
      expect(VerificationService.decidePost(_post(proves: false)).status, 'recusado');
    });
    test('fraude e conteúdo impróprio são recusados mesmo com confiança alta', () {
      expect(VerificationService.decidePost(_post(screen: true)).status, 'recusado');
      expect(VerificationService.decidePost(_post(fake: true)).status, 'recusado');
      expect(VerificationService.decidePost(_post(safe: false)).status, 'recusado');
    });
    test('resposta incompleta da IA nunca aprova', () {
      expect(VerificationService.decidePost(const {}).approved, isFalse);
      expect(VerificationService.decidePost({'conteudo_seguro': true}).approved, isFalse);
    });
  });

  group('prova de água', () {
    test('garrafa de 500 ml de 100% para 40% = 300 ml', () {
      final d = VerificationService.decideWater(_water());
      expect(d.status, 'aprovado');
      expect(d.ml, 300);
    });
    test('arredonda para baixo (múltiplos de 50 ml)', () {
      expect(VerificationService.decideWater(_water(capacity: 350, before: 90, after: 20)).ml, 200); // 245 → 200
    });
    test('na dúvida vai para a equipe, nunca aprova sozinho', () {
      expect(VerificationService.decideWater(_water(sameConf: 'media')).status, 'revisao');
      expect(VerificationService.decideWater(_water(levels: 'media')).status, 'revisao');
      expect(VerificationService.decideWater(_water(source: 'formato_conhecido')).status, 'revisao');
      expect(VerificationService.decideWater(_water(source: 'incerta', capacity: 0)).status, 'revisao');
    });
    test('recusa o que não comprova', () {
      expect(VerificationService.decideWater(_water(same: false)).status, 'recusado');
      expect(VerificationService.decideWater(_water(before: 50, after: 50)).status, 'recusado');
      expect(VerificationService.decideWater(_water(before: 40, after: 60)).status, 'recusado');
      expect(VerificationService.decideWater(_water(before: 100, after: 90, capacity: 500)).status, 'recusado'); // 50 ml
      expect(VerificationService.decideWater(_water(screen: true)).status, 'recusado');
      expect(VerificationService.decideWater(_water(capacity: 20000)).approved, isFalse);
      expect(VerificationService.decideWater(const {}).approved, isFalse);
    });
  });

  group('foto repetida (dHash)', () {
    Uint8List photo(int seed, {int quality = 90, bool crop = false}) {
      final im = img.Image(width: 320, height: 240);
      for (var y = 0; y < 240; y++) {
        for (var x = 0; x < 320; x++) {
          final v = ((x * (seed + 3) + y * (seed * 7 + 1)) ~/ 9 + seed * 37) % 256;
          im.setPixelRgb(x, y, v, (v * 3 + seed) % 256, (255 - v));
        }
      }
      final out = crop ? img.copyCrop(im, x: 6, y: 6, width: 308, height: 228) : im;
      return Uint8List.fromList(img.encodeJpg(out, quality: quality));
    }

    test('a mesma foto recomprimida ou recortada é reconhecida', () {
      final a = dHash(photo(1));
      expect(hammingDistance(a, dHash(photo(1, quality: 60))), lessThanOrEqualTo(4));
      expect(hammingDistance(a, dHash(photo(1, crop: true))), lessThanOrEqualTo(4));
    });
    test('fotos diferentes ficam longe', () {
      expect(hammingDistance(dHash(photo(1)), dHash(photo(5))), greaterThan(10));
    });
  });
}
