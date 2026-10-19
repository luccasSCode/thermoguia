import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../air/air_providers.dart';
import '../climate/climate_providers.dart';
import '../rewards/rewards_controller.dart';

/// Notificações programadas para trazer a pessoa de volta ao app na hora em
/// que ele é útil. Nada entre 19h30 e 6h30; no máximo 4 por dia.
enum Engagement {
  manha('Resumo da manhã', 'Todo dia às 6h30: o calor, a fumaça e o melhor horário para sair', 6, 30, 2),
  pico('Aviso antes do pico de calor', 'Às 10h30, só em dias de risco muito alto', 10, 30, 1),
  fimDeTarde('Janela fresca do fim da tarde', 'Às 16h30, quando a tarde refresca', 16, 30, 5),
  clube('Clube H2O: sua sequência', 'Às 19h30, se você ainda não abriu o app no dia', 19, 30, 4),
  semana('Resumo da semana', 'Domingo às 10h: trajetos, gotas e descontos', 10, 0, 3);

  const Engagement(this.title, this.when, this.hour, this.minute, this.priority);
  final String title;
  final String when;
  final int hour;
  final int minute;

  /// Menor = mais importante (para respeitar o limite diário).
  final int priority;
}

class PlannedNotification {
  const PlannedNotification(this.kind, this.at, this.title, this.body, this.route);
  final Engagement kind;
  final DateTime at;
  final String title;
  final String body;
  final String route;

  @override
  String toString() => '${kind.name} ${at.toIso8601String()} | $title | $body';
}

const maxPerDay = 4;
const _days = 7;

double _feels(HourlyPoint h) => heatIndexC(h.temperatureC, h.humidity) + (h.uvIndex >= 8 ? 2 : h.uvIndex >= 6 ? 1 : 0);

/// Monta as notificações dos próximos 7 dias. Puro, para testar.
///
/// [hourly] é a previsão já no horário do aparelho; dias sem previsão
/// recebem textos gerais (e são refeitos quando o app abre de novo).
List<PlannedNotification> planEngagement({
  required DateTime now,
  required List<HourlyPoint> hourly,
  required Set<Engagement> enabled,
  required int streak,
  required bool checkedInToday,
  required int weekEarned,
  required int weekTrips,
  required int balance,
  List<AirPoint> air = const [],
}) {
  final out = <PlannedNotification>[];
  final today = DateTime(now.year, now.month, now.day);

  for (var d = 0; d < _days; d++) {
    final day = today.add(Duration(days: d));
    DateTime at(Engagement e) => DateTime(day.year, day.month, day.day, e.hour, e.minute);
    final hours = hourly.where((h) => h.time.year == day.year && h.time.month == day.month && h.time.day == day.day).toList();
    final daytime = hours.where((h) => h.time.hour >= 9 && h.time.hour <= 17).toList();
    final peak = daytime.isEmpty ? null : daytime.reduce((a, b) => _feels(a) >= _feels(b) ? a : b);
    final late = hours.where((h) => h.time.hour >= 17 && h.time.hour <= 19).toList();
    final cool = late.isEmpty ? null : late.reduce((a, b) => _feels(a) <= _feels(b) ? a : b);

    // Fumaça entre 6h e 18h do dia: o resumo da manhã avisa.
    final smoke = air
        .where((a) => a.time.year == day.year && a.time.month == day.month && a.time.day == day.day)
        .where((a) => a.time.hour >= 6 && a.time.hour <= 18 && a.level.isBad)
        .toList();
    final smokeNote = smoke.isEmpty
        ? ''
        : 'Fumaça no ar (${smoke.map((a) => a.level).reduce((a, b) => a.index >= b.index ? a : b).label.toLowerCase()}): '
            'use máscara de proteção ao sair. ';
    final dayPlan = <PlannedNotification>[];
    void add(Engagement e, String title, String body, String route) {
      if (enabled.contains(e) && at(e).isAfter(now)) dayPlan.add(PlannedNotification(e, at(e), title, body, route));
    }

    // 6h30: resumo da manhã.
    if (d >= 3) {
      add(Engagement.manha, 'Faz alguns dias que você não aparece',
          'Veja como vai estar o calor hoje e ganhe suas gotas do dia no Clube H2O.', '/agora');
    } else if (peak != null) {
      add(
        Engagement.manha,
        'Bom dia! Hoje a sensação chega a ${_feels(peak).round()}°C',
        'O pico é por volta das ${peak.time.hour}h. '
            '$smokeNote'
            '${cool != null ? 'Prefira sair cedo ou depois das ${cool.time.hour}h. ' : 'Prefira sair cedo. '}'
            'Toque para ver o seu risco.',
        '/agora',
      );
    } else {
      add(Engagement.manha, 'Bom dia! Como vai estar o calor hoje?',
          '${smokeNote}Veja seu risco, o melhor horário para sair e sua meta de água.', '/agora');
    }

    // 10h30: só em dia de risco muito alto (índice de 38°C ou mais).
    if (peak != null && _feels(peak) >= 38) {
      add(
        Engagement.pico,
        'Calor forte chegando',
        'A sensação passa de ${_feels(peak).round()}°C perto das ${peak.time.hour}h. '
            'Se for sair, vá agora${cool != null ? ' ou depois das ${cool.time.hour}h' : ''}, pelas Rotas Frescas.',
        '/rotas',
      );
    }

    // 16h30: a tarde refrescou bem em relação ao pico.
    if (peak != null && cool != null && _feels(cool) <= _feels(peak) - 4) {
      add(
        Engagement.fimDeTarde,
        'A tarde está refrescando',
        'Às ${cool.time.hour}h a sensação cai para ${_feels(cool).round()}°C. Boa hora para caminhar ou pedalar.',
        '/rotas',
      );
    }

    // 19h30: Clube H2O (hoje só se ainda não abriu o app).
    if (d > 0 || !checkedInToday) {
      final keep = d == 1 && streak >= 1;
      add(
        Engagement.clube,
        keep ? 'Não perca sua sequência de $streak ${streak == 1 ? 'dia' : 'dias'}' : 'Suas gotas de hoje estão esperando',
        keep
            ? 'Abra o app até a meia-noite e ganhe +2 gotas. Com 7 dias seguidos, são +20.'
            : 'Abra o app, ganhe +2 gotas e veja os descontos do Clube H2O.',
        '/clube',
      );
    }

    // Domingo 10h: resumo da semana.
    if (day.weekday == DateTime.sunday) {
      add(
        Engagement.semana,
        'Sua semana no ThermoGuia',
        weekTrips > 0 || weekEarned > 0
            ? '$weekTrips ${weekTrips == 1 ? 'Rota Fresca' : 'Rotas Frescas'} e $weekEarned gotas nos últimos 7 dias. '
                'Você tem $balance gotas para trocar por descontos.'
            : 'Uma semana nova começa: faça uma Rota Fresca e ganhe gotas para trocar por descontos.',
        '/clube',
      );
    }

    dayPlan.sort((a, b) => a.kind.priority.compareTo(b.kind.priority));
    out.addAll(dayPlan.take(maxPerDay));
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Preferências (todas ligadas por padrão), salvas no aparelho.
class EngagementSettings extends Notifier<Set<Engagement>> {
  @override
  Set<Engagement> build() {
    final store = ref.read(localStoreProvider);
    return {for (final e in Engagement.values) if (store.getString('notif_${e.name}') != '0') e};
  }

  Future<void> toggle(Engagement e, bool on) async {
    state = on ? {...state, e} : ({...state}..remove(e));
    await ref.read(localStoreProvider).setString('notif_${e.name}', on ? '1' : '0');
    await rescheduleEngagement(ref);
  }
}

final engagementSettingsProvider = NotifierProvider<EngagementSettings, Set<Engagement>>(EngagementSettings.new);

/// Para widgets: `ref.read(engagementSchedulerProvider)()`.
final engagementSchedulerProvider = Provider((ref) => () => rescheduleEngagement(ref));

/// Ids reservados para as notificações programadas.
const _idBase = 100;

/// Refaz a agenda com a previsão e o Clube H2O mais recentes.
/// Chamado ao abrir o app, ao voltar para ele e ao mudar as preferências.
Future<void> rescheduleEngagement(Ref ref) async {
  final svc = ref.read(notificationServiceProvider);
  final climate = ref.read(climateProvider).valueOrNull;
  final rewards = ref.read(rewardsProvider).valueOrNull;
  final plan = planEngagement(
    now: DateTime.now(),
    hourly: climate?.hourly ?? const [],
    enabled: ref.read(engagementSettingsProvider),
    streak: rewards?.streakDays ?? 0,
    checkedInToday: rewards?.checkedInToday ?? false,
    weekEarned: rewards?.weekEarned ?? 0,
    weekTrips: rewards?.weekTrips ?? 0,
    balance: rewards?.balance ?? 0,
    air: ref.read(airProvider).valueOrNull?.hourly ?? const [],
  );
  await svc.cancelRange(_idBase, _idBase + 99);
  for (var i = 0; i < math.min(plan.length, 60); i++) {
    final p = plan[i];
    await svc.schedule(_idBase + i, p.at, p.title, p.body, route: p.route);
  }
}
