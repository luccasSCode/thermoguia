import 'package:test/test.dart';
import 'package:thermoguia_backend/services/rewards_service.dart';

void main() {
  test('níveis pelo total já ganho', () {
    expect(RewardsService.levelFor(0)['name'], 'Semente');
    expect(RewardsService.levelFor(99)['toNext'], 1);
    expect(RewardsService.levelFor(100)['name'], 'Broto');
    expect(RewardsService.levelFor(200)['progress'], 0.5);
    expect(RewardsService.levelFor(5000)['name'], 'Floresta');
    expect(RewardsService.levelFor(5000)['next'], isNull);
  });

  test('regras com limite diário onde dá para repetir', () {
    expect(RewardsService.rule('trajeto').dailyCap, 3);
    expect(RewardsService.rule('relato').dailyCap, 3);
    expect(RewardsService.rule('checkin').dailyCap, isNull); // uma vez por dia, pelo índice único
  });
}
