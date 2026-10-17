import 'dart:math' as math;

import '../cities.dart';
import '../data/repositories.dart';

/// Regra de ganho de gotas, exibida também no app ("Como ganhar").
class EarnRule {
  const EarnRule(this.reason, this.points, this.title, this.icon, {this.dailyCap});
  final String reason;
  final int points;
  final String title;
  final String icon;

  /// Quantas vezes por dia a regra paga (null = uma vez, pelo índice único).
  final int? dailyCap;

  Map<String, dynamic> toJson() => {'reason': reason, 'points': points, 'title': title, 'icon': icon};
}

/// Clube H2O: gotas por hábitos que protegem do calor, trocadas por
/// descontos em parceiros.
///
/// Grátis: ganha gotas e faz até [freeMonthlyRedeems] resgates por mês.
/// ThermoGuia+: gotas em dobro, resgates ilimitados e ofertas exclusivas.
class RewardsService {
  RewardsService(this._repo);
  final RewardRepo _repo;

  static const freeMonthlyRedeems = 2;
  static const plusMultiplier = 2;
  static const couponDays = 7;
  /// Água comprovada por foto: 1 gota a cada 100 ml, até 3 litros por dia.
  static const mlPerPoint = 100;
  static const maxVerifiedMlPerDay = 3000;

  static const rules = [
    EarnRule('checkin', 2, 'Abrir o app no dia', 'today'),
    EarnRule('sequencia', 20, 'A cada 7 dias seguidos', 'streak'),
    EarnRule('trajeto', 10, 'Concluir uma Rota Fresca (+5 se for bem sombreada)', 'route', dailyCap: 3),
    EarnRule('agua_comprovada', 1, '1 gota a cada 100 ml de água comprovados com foto (até 3 litros por dia)', 'water'),
    EarnRule('post_verificado', 5, 'Publicação verificada na Comunidade', 'camera', dailyCap: 2),
    EarnRule('selo', 50, 'Ganhar um selo da semana na Comunidade', 'badge'),
    EarnRule('relato', 5, 'Relatar sombra, água ou calor no mapa', 'report', dailyCap: 3),
  ];

  static EarnRule rule(String reason) => rules.firstWhere((r) => r.reason == reason);

  static const levels = [
    (0, 'Semente'),
    (100, 'Broto'),
    (300, 'Muda'),
    (800, 'Árvore'),
    (2000, 'Floresta'),
  ];

  static Map<String, dynamic> levelFor(int lifetime) {
    var i = 0;
    while (i + 1 < levels.length && lifetime >= levels[i + 1].$1) {
      i++;
    }
    final next = i + 1 < levels.length ? levels[i + 1] : null;
    final from = levels[i].$1;
    return {
      'name': levels[i].$2,
      'index': i,
      'next': next?.$2,
      'toNext': next == null ? 0 : next.$1 - lifetime,
      'progress': next == null ? 1.0 : (lifetime - from) / (next.$1 - from),
    };
  }

  /// Lança gotas respeitando o limite diário e o multiplicador do plano.
  /// Devolve o que foi ganho (para o app mostrar "+10 gotas") ou null.
  Future<Map<String, dynamic>?> award(
    String userId,
    String reason,
    City city, {
    required bool plus,
    int bonus = 0,
    int? basePoints,
    String? ref,
  }) async {
    final r = rule(reason);
    final today = city.localWallClock(DateTime.now());
    if (r.dailyCap != null && await _repo.countToday(userId, reason, today) >= r.dailyCap!) return null;
    final points = ((basePoints ?? r.points) + bonus) * (plus ? plusMultiplier : 1);
    if (points <= 0) return null;
    if (!await _repo.add(userId, points, reason, today, ref: ref)) return null;
    return {'points': points, 'reason': reason, 'title': r.title};
  }

  /// Gotas pela água comprovada, respeitando o teto de 3 litros por dia.
  /// Devolve também quantos ml ainda contaram hoje.
  Future<Map<String, dynamic>?> awardVerifiedWater(String userId, int ml, City city,
      {required bool plus, String? ref}) async {
    final today = city.localWallClock(DateTime.now());
    final already = await _repo.verifiedMlToday(userId, today);
    final counted = (math.min(ml, maxVerifiedMlPerDay - already) ~/ mlPerPoint) * mlPerPoint;
    if (counted <= 0) return null;
    final got = await award(userId, 'agua_comprovada', city,
        plus: plus, basePoints: counted ~/ mlPerPoint, ref: '${ref ?? ''}:$counted');
    return got == null ? null : {...got, 'ml': counted, 'title': '$counted ml de água comprovados'};
  }

  /// Check-in diário. Ao completar 7, 14, 21... dias seguidos, paga o bônus.
  Future<List<Map<String, dynamic>>> checkIn(String userId, City city, {required bool plus}) async {
    final out = <Map<String, dynamic>>[];
    final got = await award(userId, 'checkin', city, plus: plus);
    if (got == null) return out;
    out.add(got);
    final streak = await streakDays(userId, city);
    if (streak > 0 && streak % 7 == 0) {
      final bonus = await award(userId, 'sequencia', city, plus: plus, ref: '$streak');
      if (bonus != null) out.add({...bonus, 'title': '$streak dias seguidos!'});
    }
    return out;
  }

  Future<int> streakDays(String userId, City city) async {
    final days = await _repo.checkinDays(userId);
    if (days.isEmpty) return 0;
    final t = city.localWallClock(DateTime.now());
    var expected = DateTime.utc(t.year, t.month, t.day);
    // Se ainda não abriu hoje, a sequência de ontem continua valendo.
    if (_sameDay(days.first, expected.subtract(const Duration(days: 1)))) {
      expected = expected.subtract(const Duration(days: 1));
    }
    var n = 0;
    for (final d in days) {
      if (!_sameDay(d, expected)) break;
      n++;
      expected = expected.subtract(const Duration(days: 1));
    }
    return n;
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  DateTime _monthStartUtc(City city) {
    final t = city.localWallClock(DateTime.now());
    return DateTime.utc(t.year, t.month, 1).subtract(city.utcOffset);
  }

  Future<Map<String, dynamic>> summary(String userId, City city, {required bool plus}) async {
    final (balance, lifetime) = await _repo.totals(userId);
    final today = city.localWallClock(DateTime.now());
    final days = await _repo.checkinDays(userId, limit: 1);
    final checkedToday = days.isNotEmpty && _sameDay(days.first, DateTime.utc(today.year, today.month, today.day));
    final used = await _repo.redeemsSince(userId, _monthStartUtc(city));
    final (weekEarned, weekTrips) = await _repo.lastWeek(userId, today);
    final monthlyLimit = plus ? null : freeMonthlyRedeems;

    final offers = (await _repo.offers()).map((o) {
      final cost = o['cost'] as int;
      final plusOnly = o['plus_only'] as bool;
      final String? blocked = plusOnly && !plus
          ? 'Exclusivo ThermoGuia+'
          : (monthlyLimit != null && used >= monthlyLimit)
              ? 'Limite de $monthlyLimit resgates do mês atingido'
              : balance < cost
                  ? 'Faltam ${cost - balance} gotas'
                  : null;
      return {
        'id': o['id'],
        'partner': o['partner'],
        'category': o['category'],
        'title': o['title'],
        'details': o['details'],
        'neighborhood': o['neighborhood'],
        'cost': cost,
        'plusOnly': plusOnly,
        'demo': o['demo'],
        'canRedeem': blocked == null,
        'blockedReason': blocked,
      };
    }).toList();

    return {
      'balance': balance,
      'lifetime': lifetime,
      'level': levelFor(lifetime),
      'streak': {'days': await streakDays(userId, city), 'checkedInToday': checkedToday},
      'plan': {
        'plus': plus,
        'multiplier': plus ? plusMultiplier : 1,
        'monthlyLimit': monthlyLimit,
        'redeemsThisMonth': used,
      },
      'week': {'earned': weekEarned, 'trips': weekTrips},
      'rules': [for (final r in rules) r.toJson()],
      'offers': offers,
      'coupons': await _repo.activeCoupons(userId),
      'history': await _repo.history(userId),
    };
  }

  Future<(Map<String, dynamic>?, String?)> redeem(String userId, String offerId, City city, {required bool plus}) async {
    final offer = await _repo.offer(offerId);
    if (offer == null) return (null, 'Esta oferta não está mais disponível.');
    if (offer['plus_only'] == true && !plus) return (null, 'Esta oferta é exclusiva do ThermoGuia+.');
    final demo = offer['demo'] == true;
    return _repo.redeem(
      userId: userId,
      offer: offer,
      localDay: city.localWallClock(DateTime.now()),
      monthStartUtc: _monthStartUtc(city),
      monthlyLimit: plus ? null : freeMonthlyRedeems,
      // Cupons de exemplo são marcados no código, para ninguém tentar usá-los numa loja.
      code: '${demo ? 'EXEMPLO-' : 'TG-'}${_code()}',
      expires: DateTime.now().toUtc().add(const Duration(days: couponDays)),
    );
  }

  static final _rnd = math.Random.secure();
  static String _code() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    return List.generate(6, (_) => chars[_rnd.nextInt(chars.length)]).join();
  }
}
