import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../session/presentation/session_controller.dart';
import 'air_providers.dart';
import 'air_repository.dart';

String _n(double v, [int digits = 1]) => v.toStringAsFixed(digits).replaceAll('.', ',');

/// "Ar de hoje": índice CONAMA, cigarros invisíveis, máscara e a Hora Segura.
/// Some quando não há dados (o resto da tela Agora não depende dele).
class AirQualityCard extends ConsumerWidget {
  const AirQualityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final air = ref.watch(airProvider).valueOrNull;
    final advice = ref.watch(airAdviceProvider);
    if (air == null || advice == null) return const SizedBox.shrink();
    final persona = ref.watch(personaProvider);
    final windows = ref.watch(safeWindowsProvider);
    final sun = context.sunMode;
    final level = air.current.level;
    final color = Tokens.air(level, sunMode: sun);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final day = cigarettesFor(air.current.pm25);
    final hour = cigarettesFor(air.current.pm25, hours: 1, breathing: breathingFactor(persona));

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 16, 12, 0),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusSheet),
        color: sun ? Colors.white : null,
        border: sun ? Border.all(color: Colors.black, width: 2) : Border.all(color: color.withValues(alpha: 0.5)),
        gradient: sun
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [color.withValues(alpha: 0.16), scheme.surface],
              ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusSheet),
          onTap: () => showAirDetails(context),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.air, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text('Qualidade do ar', style: t.titleMedium)),
                  if (air.stale) Icon(Icons.history, size: 18, color: scheme.outline),
                ]),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${air.current.index}',
                      style: t.displayMedium?.copyWith(height: 1, color: color, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(level.label, style: t.titleLarge?.copyWith(color: color)),
                          Text('Fumaça (PM2.5): ${air.current.pm25.round()} µg/m³', style: t.bodySmall),
                        ]),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _AdviceRow(advice: advice, color: color),
                if (day >= 0.5) ...[
                  const SizedBox(height: 12),
                  _CigaretteRow(day: day, hour: hour, persona: persona),
                ],
                const SizedBox(height: 14),
                _ForecastStrip(air: air),
                const SizedBox(height: 12),
                _SafeHours(windows: windows),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(padding: EdgeInsets.zero),
                    onPressed: () => showAirDetails(context),
                    child: const Text('Como se proteger da fumaça'),
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

class _AdviceRow extends StatelessWidget {
  const _AdviceRow({required this.advice, required this.color});
  final AirAdvice advice;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(advice.mask ? Icons.masks_outlined : Icons.directions_walk, size: 28, color: color),
      const SizedBox(width: 12),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(advice.title, style: t.titleSmall),
          const SizedBox(height: 2),
          Text(advice.message, style: t.bodyMedium),
        ]),
      ),
    ]);
  }
}

/// Cigarros invisíveis: a fumaça em uma unidade que todo mundo entende.
class _CigaretteRow extends StatelessWidget {
  const _CigaretteRow({required this.day, required this.hour, required this.persona});
  final double day;
  final double hour;
  final Persona persona;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final factor = breathingFactor(persona);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.smoking_rooms_outlined, size: 26, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              'Respirar este ar por um dia = ${_n(day)} ${day >= 1.95 || day < 0.95 ? 'cigarros' : 'cigarro'}',
              style: t.titleSmall,
            ),
            const SizedBox(height: 2),
            Text(
              factor >= 1.3
                  ? 'Como ${persona.label.toLowerCase()}, você respira ${_n(factor)}× mais ar. '
                      '1 hora na rua agora ≈ ${_n(hour, 2)} cigarro.'
                  : '1 hora na rua agora ≈ ${_n(hour, 2)} cigarro.',
              style: t.bodySmall,
            ),
          ]),
        ),
      ]),
    );
  }
}

/// Barras coloridas das próximas 24 horas, para ver quando a fumaça vem e vai.
class _ForecastStrip extends StatelessWidget {
  const _ForecastStrip({required this.air});
  final AirData air;

  @override
  Widget build(BuildContext context) {
    final hours = air.next(24);
    if (hours.length < 6) return const SizedBox.shrink();
    final sun = context.sunMode;
    final t = Theme.of(context).textTheme;
    final top = hours.map((h) => h.index).reduce((a, b) => a > b ? a : b).clamp(80, 400);
    return Semantics(
      label: 'Previsão da qualidade do ar nas próximas 24 horas',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Próximas 24 horas', style: t.labelLarge),
          const SizedBox(height: 6),
          SizedBox(
            height: 44,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final h in hours)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1),
                    child: FractionallySizedBox(
                      heightFactor: (h.index / top).clamp(0.12, 1.0),
                      alignment: Alignment.bottomCenter,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Tokens.air(h.level, sunMode: sun),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 4),
          Row(children: [
            for (var i = 0; i < hours.length; i++)
              Expanded(
                child: i % 6 == 0
                    ? Text('${hours[i].time.hour}h', style: t.labelSmall, softWrap: false, overflow: TextOverflow.visible)
                    : const SizedBox.shrink(),
              ),
          ]),
        ]),
      ),
    );
  }
}

class _SafeHours extends StatelessWidget {
  const _SafeHours({required this.windows});
  final List<SafeWindow> windows;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    if (windows.isEmpty) {
      return Row(children: [
        const Icon(Icons.shield_outlined, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Sem Hora Segura nas próximas 24h: se precisar sair, use PFF2.', style: t.bodyMedium),
        ),
      ]);
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Hora Segura:', style: t.titleSmall),
        for (final w in windows)
          Chip(
            avatar: const Icon(Icons.verified_user_outlined, size: 18, color: Tokens.copa),
            label: Text('${w.rangeLabel} · ${w.feelsC.round()}°'),
          ),
      ],
    );
  }
}

/// Explicação completa: escala, o que é a Hora Segura e como proteger a casa.
void showAirDetails(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (ctx, scroll) => _AirDetails(scroll: scroll),
    ),
  );
}

class _AirDetails extends ConsumerWidget {
  const _AirDetails({required this.scroll});
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final sun = context.sunMode;
    final current = ref.watch(airProvider).valueOrNull?.current.level;
    final alerts = ref.watch(airAlertsSettingProvider);
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      children: [
        Text('Fumaça e qualidade do ar', style: t.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Na época das queimadas, a fumaça cobre Manaus inteira, até as áreas arborizadas. '
          'O ThermoGuia mede as partículas finas (PM2.5), que entram fundo no pulmão, e '
          'traduz o número no índice oficial brasileiro.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 16),
        for (final l in AirLevel.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 14,
                height: 14,
                margin: const EdgeInsets.only(top: 3),
                decoration: BoxDecoration(color: Tokens.air(l, sunMode: sun), shape: BoxShape.circle),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '${l.label}${l == current ? ' (agora)' : ''}  ',
                    style: t.titleSmall,
                  ),
                  TextSpan(text: l.summary, style: t.bodyMedium),
                ])),
              ),
            ]),
          ),
        const SizedBox(height: 12),
        Text('Hora Segura', style: t.titleMedium),
        const SizedBox(height: 4),
        Text(
          'São os horários em que o ar está bom ou moderado e a sensação térmica fica abaixo '
          'de 38 °C. É o melhor momento para caminhar, pedalar ou resolver coisas na rua.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 16),
        Text('Como se proteger', style: t.titleMedium),
        const SizedBox(height: 8),
        const _Tip(Icons.masks_outlined,
            'Máscara PFF2 (ou N95) filtra a fumaça; a de pano e a cirúrgica, não. Ajuste bem no nariz.'),
        const _Tip(Icons.window_outlined,
            'Com ar ruim, feche janelas e portas. Abra quando o ThermoGuia avisar que o ar melhorou.'),
        const _Tip(Icons.water_drop_outlined, 'Beba mais água: ajuda a aliviar a garganta e os olhos.'),
        const _Tip(Icons.directions_bus_outlined,
            'Evite pedalar ou correr na fumaça: com esforço, você respira até 2× mais partículas.'),
        const _Tip(Icons.local_hospital_outlined,
            'Falta de ar, chiado, dor no peito ou tontura: procure atendimento. Crianças, idosos e '
            'gestantes são mais sensíveis.'),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Alertas de fumaça'),
          subtitle: const Text('Aviso antes de a fumaça chegar e quando o ar fica bom para sair'),
          value: alerts,
          onChanged: (on) => ref.read(airAlertsSettingProvider.notifier).set(on),
        ),
        const SizedBox(height: 8),
        Text(
          'Fontes: previsão CAMS (Copernicus) via Open-Meteo; índice da Resolução CONAMA 491/2018; '
          'equivalência em cigarros da Berkeley Earth (22 µg/m³ por um dia ≈ 1 cigarro). '
          'O índice usa a média de cada hora, não a de 24 horas dos boletins oficiais.',
          style: t.bodySmall,
        ),
      ],
    );
  }
}

class _Tip extends StatelessWidget {
  const _Tip(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 24, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ]),
      );
}
