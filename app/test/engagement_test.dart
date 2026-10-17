import 'package:flutter_test/flutter_test.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:thermoguia/features/notifications/engagement.dart';

/// Quarta, 14/10/2026. Previsão de 48h: pico de 35°C às 13h, 26°C a partir das 18h.
List<HourlyPoint> _forecast(DateTime from) => [
      for (var i = 0; i < 48; i++)
        (() {
          final t = from.add(Duration(hours: i));
          final h = t.hour;
          final temp = h >= 11 && h <= 15 ? 35.0 : (h >= 18 || h <= 6 ? 26.0 : 30.0);
          return HourlyPoint(time: t, temperatureC: temp, humidity: 65, uvIndex: h >= 10 && h <= 14 ? 10 : 2, precipitationProb: 10);
        })(),
    ];

List<PlannedNotification> _plan(DateTime now, {Set<Engagement>? enabled, bool checkedIn = true, int streak = 3}) =>
    planEngagement(
      now: now,
      hourly: _forecast(DateTime(now.year, now.month, now.day)),
      enabled: enabled ?? Engagement.values.toSet(),
      streak: streak,
      checkedInToday: checkedIn,
      weekEarned: 85,
      weekTrips: 3,
      balance: 120,
    );

void main() {
  final morning = DateTime(2026, 10, 14, 6, 0);

  test('horários definidos e nada entre 19h30 e 6h30', () {
    for (final p in _plan(morning)) {
      final m = p.at.hour * 60 + p.at.minute;
      expect(m >= 6 * 60 + 30 && m <= 19 * 60 + 30, isTrue, reason: '$p');
      expect(p.at.isAfter(morning), isTrue);
    }
  });

  test('no máximo 4 por dia, por 7 dias', () {
    final plan = _plan(morning);
    final perDay = <int, int>{};
    for (final p in plan) {
      perDay[p.at.day] = (perDay[p.at.day] ?? 0) + 1;
    }
    expect(perDay.values.every((n) => n <= maxPerDay), isTrue);
    expect(perDay.length, 7);
  });

  test('dia quente: resumo da manhã com o pico, aviso às 10h30 e janela fresca', () {
    final today = _plan(morning).where((p) => p.at.day == 14).toList();
    final kinds = today.map((p) => p.kind).toSet();
    expect(kinds, containsAll([Engagement.manha, Engagement.pico, Engagement.fimDeTarde]));
    final manha = today.firstWhere((p) => p.kind == Engagement.manha);
    expect(manha.at, DateTime(2026, 10, 14, 6, 30));
    expect(manha.title, contains('°C'));
    expect(today.firstWhere((p) => p.kind == Engagement.pico).route, '/rotas');
  });

  test('Clube: hoje só se não abriu o app; amanhã lembra a sequência', () {
    expect(_plan(morning).any((p) => p.kind == Engagement.clube && p.at.day == 14), isFalse);
    expect(_plan(morning, checkedIn: false).any((p) => p.kind == Engagement.clube && p.at.day == 14), isTrue);
    final tomorrow = _plan(morning).firstWhere((p) => p.kind == Engagement.clube && p.at.day == 15);
    expect(tomorrow.title, 'Não perca sua sequência de 3 dias');
    expect(tomorrow.route, '/clube');
  });

  test('resumo da semana no domingo às 10h', () {
    final sunday = _plan(morning).firstWhere((p) => p.kind == Engagement.semana);
    expect(sunday.at, DateTime(2026, 10, 18, 10, 0));
    expect(sunday.body, contains('3 Rotas Frescas e 85 gotas'));
  });

  test('sem previsão: textos gerais; depois de 3 dias, convite para voltar', () {
    final plan = planEngagement(
      now: morning, hourly: const [], enabled: Engagement.values.toSet(),
      streak: 0, checkedInToday: true, weekEarned: 0, weekTrips: 0, balance: 0,
    );
    expect(plan.where((p) => p.kind == Engagement.pico), isEmpty);
    expect(plan.firstWhere((p) => p.at.day == 14).title, 'Bom dia! Como vai estar o calor hoje?');
    expect(plan.firstWhere((p) => p.at.day == 17 && p.kind == Engagement.manha).title, contains('alguns dias'));
  });

  test('respeita o que a pessoa desligou', () {
    final plan = _plan(morning, enabled: {Engagement.manha});
    expect(plan.every((p) => p.kind == Engagement.manha), isTrue);
  });
}
