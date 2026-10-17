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
import '../climate/climate_providers.dart';
import '../hydration/hydration_controller.dart';
import '../outdoor/outdoor_session_controller.dart';
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
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(briefingProvider);
            await ref.read(climateProvider.notifier).refresh();
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
                const _Shortcuts(),
                const _BriefingBlock(),
                const _OutdoorBlock(),
                const _HydrationBlock(),
                const _ClubCard(),
                const _WindowsBlock(),
                const _RecommendationsBlock(),
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
    );
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
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () {
              ref.invalidate(briefingProvider);
              ref.read(climateProvider.notifier).refresh();
            },
          ),
        ],
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
      margin: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusSheet),
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
          Text('Sensação para você', style: t.titleMedium),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${risk.effectiveIndexC.round()}°',
                style: t.displayLarge?.copyWith(fontSize: 88, height: 1, color: color, letterSpacing: -3),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('Risco ${risk.level.label.toLowerCase()}', style: t.titleLarge?.copyWith(color: color)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(risk.level.summary, style: t.bodyLarge),
          const SizedBox(height: 16),
          HeatBand(score: risk.score, level: risk.level),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _Metric('Temperatura', '${climate.temperatureC.round()}°'),
              _Metric('Umidade', '${climate.humidity.round()}%'),
              _Metric('UV', climate.isDay ? climate.uvIndex.round().toString() : '0'),
              _Metric('Chuva', '${climate.precipitationProb.round()}%'),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: () => _explain(context, ref, risk),
              child: Text('Por que ${risk.effectiveIndexC.round()}°?'),
            ),
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
  const _Metric(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Theme.of(context).textTheme.titleLarge),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _BriefingBlock extends ConsumerWidget {
  const _BriefingBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final b = ref.watch(briefingProvider);
    final text = b.whenOrNull(data: (x) => x.text);
    if (text == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: InkWell(
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        onTap: () => context.go('/assistente'),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.auto_awesome, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 12),
            Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyLarge)),
          ],
        ),
      ),
    );
  }
}

class _OutdoorBlock extends ConsumerWidget {
  const _OutdoorBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(outdoorSessionProvider);
    final risk = ref.watch(riskProvider);
    return Column(
      children: [
        const SectionTitle('Na rua'),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 20),
          value: s.active,
          onChanged: (_) => ref.read(outdoorSessionProvider.notifier).toggle(),
          title: const Text('Estou na rua agora'),
          subtitle: Text(s.active && risk != null
              ? 'Contando seu tempo ao sol. Lembrete de água a cada ${risk.hydrationIntervalMin} min.'
              : 'Hoje: ${s.minutesToday} min ao sol. Ative para receber lembretes.'),
        ),
      ],
    );
  }
}

/// Botões dedicados para o Clube H2O e os Planos: só abrem com um toque.
class _Shortcuts extends ConsumerWidget {
  const _Shortcuts();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPlus = ref.watch(sessionProvider.select((s) => s.user?.isPlus ?? false));
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
              icon: const Icon(Icons.workspace_premium_outlined),
              label: label(isPlus ? 'ThermoGuia+' : 'Planos'),
              onPressed: () => context.push('/planos'),
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

class _WindowsBlock extends ConsumerWidget {
  const _WindowsBlock();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final w = ref.watch(comfortWindowsProvider);
    if (w.best.isEmpty) return const SizedBox.shrink();
    final habitual = ref.watch(adaptiveProvider.select((p) => p.habitualHours));
    final t = Theme.of(context).textTheme;
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
              for (final x in w.best)
                Chip(
                  avatar: Icon(Icons.schedule, size: 18, color: Tokens.risk(x.level, sunMode: context.sunMode)),
                  label: Text('${x.rangeLabel}  ${x.avgHeatIndexC.round()}°'),
                ),
            ],
          ),
        ),
        if (w.avoid != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Text('Evite sair entre ${w.avoid!.rangeLabel}, o período mais quente.', style: t.bodyLarge),
          ),
        if (habitual.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'Você costuma sair às ${habitual.map((h) => '${h}h').join(' e ')}. '
              'Vamos te avisar se esse horário ficar perigoso.',
              style: t.bodyMedium,
            ),
          ),
      ],
    );
  }
}

class _RecommendationsBlock extends ConsumerWidget {
  const _RecommendationsBlock();

  IconData _icon(RecommendationKind k) => switch (k) {
        RecommendationKind.hidratacao => Icons.water_drop_outlined,
        RecommendationKind.sombra => Icons.park_outlined,
        RecommendationKind.horario => Icons.schedule,
        RecommendationKind.saude => Icons.favorite_border,
        RecommendationKind.rota => Icons.alt_route,
        RecommendationKind.roupa => Icons.wb_sunny_outlined,
        RecommendationKind.chuva => Icons.umbrella_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recs = ref.watch(riskProvider)?.recommendations ?? const [];
    if (recs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionTitle('O que fazer agora'),
        for (final r in recs.take(4))
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            leading: Icon(_icon(r.kind), size: 28),
            title: Text(r.title, style: Theme.of(context).textTheme.titleMedium),
            subtitle: Text(r.message),
            onTap: r.kind == RecommendationKind.sombra ? () => context.go('/rotas') : null,
          ),
      ],
    );
  }
}
