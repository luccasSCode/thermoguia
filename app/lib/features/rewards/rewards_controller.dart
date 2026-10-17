import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';

/// Resumo do Clube H2O vindo do servidor (saldo, nível, sequência,
/// ofertas, cupons e histórico).
class RewardsSummary {
  const RewardsSummary(this.raw);
  final Map<String, dynamic> raw;

  int get balance => raw['balance'] as int;
  int get lifetime => raw['lifetime'] as int;
  Map<String, dynamic> get level => (raw['level'] as Map).cast<String, dynamic>();
  int get streakDays => ((raw['streak'] as Map)['days'] as num).toInt();
  bool get checkedInToday => (raw['streak'] as Map)['checkedInToday'] == true;
  Map<String, dynamic> get plan => (raw['plan'] as Map).cast<String, dynamic>();
  bool get isPlus => plan['plus'] == true;
  int get weekEarned => ((raw['week'] as Map)['earned'] as num).toInt();
  int get weekTrips => ((raw['week'] as Map)['trips'] as num).toInt();
  List<Map<String, dynamic>> _list(String k) =>
      (raw[k] as List? ?? const []).map((e) => (e as Map).cast<String, dynamic>()).toList();
  List<Map<String, dynamic>> get rules => _list('rules');
  List<Map<String, dynamic>> get offers => _list('offers');
  List<Map<String, dynamic>> get coupons => _list('coupons');
  List<Map<String, dynamic>> get history => _list('history');
}

/// Gotas recém-ganhas, para o aviso "+10 gotas" no app.
class RewardEvent {
  const RewardEvent(this.points, this.title);
  final int points;
  final String title;
}

final rewardEventProvider = StateProvider<RewardEvent?>((_) => null);

class RewardsController extends AsyncNotifier<RewardsSummary> {
  @override
  Future<RewardsSummary> build() async =>
      RewardsSummary(((await ref.read(apiClientProvider).get('/rewards')) as Map).cast<String, dynamic>());

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  /// Check-in do dia (abrir o app). Idempotente no servidor.
  Future<void> checkIn() async {
    try {
      final res = (await ref.read(apiClientProvider).post('/rewards/checkin') as Map).cast<String, dynamic>();
      for (final e in (res['earned'] as List? ?? const [])) {
        _announce((e as Map).cast<String, dynamic>());
      }
    } catch (_) {/* sem conexão: tenta de novo na próxima abertura */}
    await refresh();
  }

  /// Respostas de /hydration, /trips e /reports trazem `reward` quando
  /// renderam gotas.
  void announceFrom(Object? response) {
    if (response is! Map || response['reward'] is! Map) return;
    _announce((response['reward'] as Map).cast<String, dynamic>());
    refresh();
  }

  void _announce(Map<String, dynamic> r) =>
      ref.read(rewardEventProvider.notifier).state = RewardEvent((r['points'] as num).toInt(), r['title'] as String);

  /// Troca gotas por um cupom. Lança [ApiException] com o motivo se não der.
  Future<Map<String, dynamic>> redeem(String offerId) async {
    final c = (await ref.read(apiClientProvider).post('/rewards/redeem', {'offerId': offerId}) as Map)
        .cast<String, dynamic>();
    await refresh();
    return c;
  }
}

final rewardsProvider = AsyncNotifierProvider<RewardsController, RewardsSummary>(RewardsController.new);
