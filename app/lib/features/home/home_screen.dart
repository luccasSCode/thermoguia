import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/heat_band.dart';
import '../../core/widgets/thermo_logo.dart';
import '../adaptive/adaptive_controller.dart';
import '../air/air_card.dart';
import '../air/air_providers.dart';
import '../climate/climate_providers.dart';
import '../climate/weather_alert_popup.dart';
import '../hydration/hydration_controller.dart';
import '../safety/emergency_sheet.dart';
import '../session/presentation/session_controller.dart';
import 'briefing_provider.dart';
import '../../core/widgets/thermo_loader.dart';
import 'greeting.dart';
import '../rewards/rewards_controller.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(adaptiveProvider.notifier).syncFromServer();
      ref.read(auditLoggerProvider).flush();
      ref.read(hydrationProvider.notifier).ensureToday();
    });
  }

  @override
  Widget build(BuildContext context) {
    final climate = ref.watch(climateProvider);
    return WeatherAlertWatcher(
        child: Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(briefingProvider);
            await Future.wait([
              ref.read(climateProvider.notifier).refresh(),
              ref.read(airProvider.notifier).refresh(),
            ]);
          },
          child: climate.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: true,
            loading: () => const Center(child: ThermoLoader()),
            error: (e, _) => ListView(children: [
              const _TopBar(),
              ErrorView(error: e, onRetry: () => ref.read(climateProvider.notifier).refresh()),
            ]),
            data: (c) => ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const _TopBar(),
                if (c.stale)
                  const _Notice(icon: Icons.history, text: 'Sem conexão: mostrando os últimos dados salvos.'),
                const _LocationNotice(),
                _Hero(climate: c.current),
                const AirQualityCard(),
                const _BriefingBlock(),
                const _WindowsBlock(),
                const _RecommendationsBlock(),
                const _Shortcuts(),
                const _HydrationBlock(),
                const _ClubCard(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                      side: BorderSide(color: Theme.of(context).colorScheme.error, width: 2),
                    ),
                    onPressed: () => showEmergencySheet(context, trigger: 'usuario'),
                    icon: const Icon(Icons.emergency_outlined),
                    label: const Text('Estou passando mal'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}

class _TopBar extends ConsumerWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(sessionProvider.select((s) => s.user?.firstName ?? ''));
    final greet = ref.watch(dayPeriodProvider).greeting;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
      child: Row(
        children: [
          const ThermoLogo(size: 40),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              name.isEmpty ? greet : '$greet, $name',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const _Bell(),
        ],
      ),
    );
  }
}

/// Sino com as notificações recebidas; a bolinha mostra quantas são novas.
class _Bell extends ConsumerWidget {
  const _Bell();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(notificationInboxProvider.select((i) => i.unread));
    return IconButton(
      tooltip: unread == 0 ? 'Notificações' : '$unread notificações novas',
      onPressed: () => context.push('/notificacoes'),
      icon: Badge(
        isLabelVisible: unread > 0,
        label: Text(unread > 9 ? '9+' : '$unread'),
        backgroundColor: Tokens.sol,
        child: Icon(unread > 0 ? Icons.notifications_active_outlined : Icons.notifications_none),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text, this.action});
  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
        child: Row(
          children: [
            Icon(icon, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
            if (action != null) action!,
          ],
        ),
      );
}

class _LocationNotice extends ConsumerWidget {
  const _LocationNotice();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loc = ref.watch(userLocationProvider).valueOrNull;
    if (loc == null || !loc.isApproximate) return const SizedBox.shrink();
    return _Notice(
      icon: Icons.location_off_outlined,
      text: 'Sem GPS: usando o centro de Manaus.',
      action: TextButton(
        onPressed: () async {
          await ref.read(locationServiceProvider).openSettings();
          ref.read(climateProvider.notifier).relocate();
        },
        child: const Text('Ativar'),
      ),
    );
  }
}

class _Hero extends ConsumerWidget {
  const _Hero({required this.climate});
  final ClimateSnapshot climate;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final risk = ref.watch(riskProvider);
    if (risk == null) return const SizedBox.shrink();
    final sun = context.sunMode;
    final color = Tokens.risk(risk.level, sunMode: sun);
    final t = Theme.of(context).textTheme;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        color: sun ? Colors.white : null,
        border: sun ? Border.all(color: Colors.black, width: 2) : null,
        gradient: sun
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.16), Theme.of(context).colorScheme.surface],
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${risk.effectiveIndexC.round()}°',
                style:
                    t.displaySmall?.copyWith(height: 1, color: color, fontWeight: FontWeight.w700, letterSpacing: -1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Sensação para você', style: t.labelLarge),
                  Text('Risco ${risk.level.label.toLowerCase()}',
                      style: t.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                ]),
              ),
              TextButton(onPressed: () => _explain(context, ref, risk), child: const Text('Por quê?')),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Metric(Icons.thermostat, '${climate.temperatureC.round()}°', 'Temperatura'),
              _Metric(Icons.water_drop_outlined, '${climate.humidity.round()}%', 'Umidade'),
              _Metric(Icons.wb_sunny_outlined, climate.isDay ? climate.uvIndex.round().toString() : '0', 'Índice UV'),
              _Metric(Icons.umbrella_outlined, '${climate.precipitationProb.round()}%', 'Chuva'),
              const SizedBox(width: 4),
            ],
          ),
        ],
      ),
    );
  }

  void _explain(BuildContext context, WidgetRef ref, RiskAssessment risk) {
    final parts = ref.read(riskBreakdownProvider);
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text('Como chegamos nesse número', style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(risk.level.summary, style: Theme.of(ctx).textTheme.bodyLarge),
            const SizedBox(height: 12),
            HeatBand(score: risk.score, level: risk.level),
            const SizedBox(height: 16),
            _Line('Índice de calor (temperatura + umidade)', risk.heatIndexC),
            for (final e in parts.entries) _Line(e.key, e.value, signed: true),
            const Divider(height: 24),
            _Line('Sensação para você', risk.effectiveIndexC, bold: true),
            const SizedBox(height: 12),
            Text(
              '"Sua sensibilidade" é aprendida com as respostas que você dá ao final dos trajetos.',
              style: Theme.of(ctx).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.signed = false, this.bold = false});
  final String label;
  final double value;
  final bool signed;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final v = value.toStringAsFixed(1).replaceAll('.', ',');
    final style = Theme.of(context).textTheme.bodyLarge?.copyWith(fontWeight: bold ? FontWeight.w800 : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Expanded(child: Text(label, style: style)),
        Text(signed ? '${value >= 0 ? '+' : ''}$v °C' : '$v °C', style: style),
      ]),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.icon, this.value, this.label);
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '$label $value',
        child: ExcludeSemantics(
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(value, style: Theme.of(context).textTheme.labelLarge),
          ]),
        ),
      );
}

/// Resumo do assistente (calor, ar e o que fazer), logo abaixo dos números.
class _BriefingBlock extends ConsumerWidget {
  const _BriefingBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(briefingProvider);
    final text = b.whenOrNull(data: (x) => x.text);
    if (text == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Material(
        color: scheme.primaryContainer.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          onTap: () => context.go('/assistente'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.auto_awesome, color: scheme.primary),
                const SizedBox(width: 12),
                Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botões dedicados para o Clube H2O e as doações: só abrem com um toque.
class _Shortcuts extends ConsumerWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Widget label(String text) => FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Row(children: [
        Expanded(
          child: _GradientOutline(
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.water_drop),
              label: label('Clube H2O'),
              onPressed: () => context.push('/clube'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _GradientOutline(
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.volunteer_activism_outlined),
              label: label('Apoiar'),
              onPressed: () => context.push('/apoiar'),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Contorno com o degradê verde da logo em volta de um botão.
class _GradientOutline extends StatelessWidget {
  const _GradientOutline({required this.child});
  final Widget child;

  static const _width = 2.0;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          gradient: Tokens.logoGradient,
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_width),
          child: FilledButtonTheme(
            data: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusControl - _width)),
              ).merge(FilledButtonTheme.of(context).style),
            ),
            child: child,
          ),
        ),
      );
}

/// Resumo do Clube H2O: saldo, sequência e o próximo desconto. Para entrar no
/// Clube, use o botão dedicado em [_Shortcuts].
class _ClubCard extends ConsumerWidget {
  const _ClubCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(rewardsProvider).valueOrNull;
    if (s == null) return const SizedBox.shrink();
    final t = Theme.of(context).textTheme;
    final ready = s.offers.where((o) => o['canRedeem'] == true).length;
    final cheapest = s.offers
        .where((o) => o['plusOnly'] != true)
        .map((o) => o['cost'] as int)
        .fold<int?>(null, (m, c) => m == null || c < m ? c : m);
    final hint = ready > 0
        ? '$ready ${ready == 1 ? 'desconto disponível' : 'descontos disponíveis'} para trocar'
        : cheapest != null && cheapest > s.balance
            ? 'Faltam ${cheapest - s.balance} gotas para o primeiro desconto'
            : 'Ganhe gotas cuidando de você no calor';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
      child: Material(
        color: Tokens.rio.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const Icon(Icons.water_drop, color: Tokens.rio, size: 36),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Clube H2O · ${s.balance} gotas', style: t.titleMedium),
                const SizedBox(height: 2),
                Text(hint, style: t.bodyMedium),
              ]),
            ),
            if (s.streakDays > 0) ...[
              const Icon(Icons.local_fire_department, color: Tokens.sol),
              Text('${s.streakDays}', style: t.titleMedium),
            ],
          ]),
        ),
      ),
    );
  }
}

class _HydrationBlock extends ConsumerWidget {
  const _HydrationBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(hydrationProvider);
    final goal = ref.watch(riskProvider)?.waterGoalMl ?? 2500;
    final progress = (h.totalMl / goal).clamp(0.0, 1.0);
    final t = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          'Água hoje',
          trailing: h.entries.isEmpty
              ? null
              : TextButton(
                  onPressed: () => ref.read(hydrationProvider.notifier).undoLast(),
                  child: const Text('Desfazer'),
                ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${h.totalMl} de $goal ml', style: t.titleMedium),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: context.sunMode ? 16 : 10,
                  color: Tokens.rio,
                  backgroundColor: Tokens.rio.withValues(alpha: 0.15),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final ml in const [200, 350, 500]) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => ref.read(hydrationProvider.notifier).add(ml),
                        child: Text('+ $ml ml'),
                      ),
                    ),
                    if (ml != 500) const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 4),
              // Os botões servem para o seu controle; gotas só com prova por foto.
              TextButton.icon(
                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                label: const Text('Comprove com foto e ganhe gotas no Clube H2O'),
                onPressed: () => context.go('/comunidade'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Melhores horários para sair. Com fumaça, mostra a Hora Segura (ar limpo
/// e calor suportável); sem dados do ar, só o calor.
class _WindowsBlock extends ConsumerWidget {
  const _WindowsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(comfortWindowsProvider);
    final safe = ref.watch(safeWindowsProvider);
    final air = ref.watch(airProvider).valueOrNull;
    final smoky = air != null && air.next(24).any((h) => h.level.isBad);
    if (w.best.isEmpty && safe.isEmpty) return const SizedBox.shrink();
    final habitual = ref.watch(adaptiveProvider.select((p) => p.habitualHours));
    final t = Theme.of(context).textTheme;
    final sun = context.sunMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('Melhores horários para sair'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (smoky)
                for (final x in safe)
                  Chip(
                    avatar: const Icon(Icons.verified_user_outlined, size: 18, color: Tokens.copa),
                    label: Text('${x.rangeLabel} · ${x.feelsC.round()}° · ar limpo'),
                  )
              else
                for (final x in w.best)
                  Chip(
                    avatar: Icon(Icons.schedule, size: 18, color: Tokens.risk(x.level, sunMode: sun)),
                    label: Text('${x.rangeLabel}  ${x.avgHeatIndexC.round()}°'),
                  ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
          child: Text(
            [
              if (smoky && safe.isEmpty)
                'Com a fumaça, não há horário de ar limpo nas próximas 24h: se sair, use máscara de proteção.',
              if (smoky && safe.isNotEmpty) 'Nesses horários o ar fica limpo e o calor é suportável (Hora Segura).',
              if (w.avoid != null) 'Evite sair entre ${w.avoid!.rangeLabel}, o período mais quente.',
              if (habitual.isNotEmpty)
                'Você costuma sair às ${habitual.map((h) => '${h}h').join(' e ')}: vamos avisar se esse horário ficar perigoso.',
            ].join(' '),
            style: t.bodyMedium,
          ),
        ),
      ],
    );
  }
}

/// "O que fazer agora": cartões coloridos lado a lado. Com fumaça, a
/// recomendação do ar vem primeiro.
class _RecommendationsBlock extends ConsumerWidget {
  const _RecommendationsBlock();

  static (IconData, Color) _style(RecommendationKind k) => switch (k) {
        RecommendationKind.hidratacao => (Icons.water_drop_outlined, Tokens.rio),
        RecommendationKind.sombra => (Icons.park_outlined, Tokens.copa),
        RecommendationKind.horario => (Icons.schedule, const Color(0xFF6B5BD2)),
        RecommendationKind.saude => (Icons.favorite_border, const Color(0xFFD9542B)),
        RecommendationKind.rota => (Icons.alt_route, Tokens.copa),
        RecommendationKind.roupa => (Icons.wb_sunny_outlined, Tokens.sol),
        RecommendationKind.chuva => (Icons.umbrella_outlined, Tokens.rio),
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(riskProvider)?.recommendations ?? const [];
    final air = ref.watch(airAdviceProvider);
    final cards = <Widget>[
      if (air != null && air.mask)
        _RecCard(
          icon: Icons.masks_outlined,
          color: Tokens.air(air.level, sunMode: context.sunMode),
          title: air.title,
          message: air.message,
          onTap: () => showAirDetails(context),
        ),
      ...recs.take(4).map((r) {
        final (icon, color) = _style(r.kind);
        return _RecCard(
          icon: icon,
          color: color,
          title: r.title,
          message: r.message,
          onTap: r.kind == RecommendationKind.sombra || r.kind == RecommendationKind.rota
              ? () => context.go('/rotas')
              : null,
        );
      }),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('O que fazer agora'),
        SizedBox(
          height: 168,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cards.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) => cards[i],
          ),
        ),
      ],
    );
  }
}

class _RecCard extends StatelessWidget {
  const _RecCard({required this.icon, required this.color, required this.title, required this.message, this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SizedBox(
      width: 240,
      child: Material(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                  child: Icon(icon, color: Colors.white, size: 20),
                ),
                const Spacer(),
                if (onTap != null) Icon(Icons.arrow_forward, size: 18, color: color),
              ]),
              const SizedBox(height: 10),
              Text(title,
                  style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 4),
              Expanded(
                child: Text(message, style: t.bodySmall, maxLines: 4, overflow: TextOverflow.ellipsis),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
