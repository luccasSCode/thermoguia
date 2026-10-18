import 'package:flutter/material.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/theme/tokens.dart';

IconData personaIcon(Persona p) => switch (p) {
      Persona.pedestre => Icons.directions_walk,
      Persona.ciclista => Icons.directions_bike,
      Persona.entregador => Icons.delivery_dining,
      Persona.vendedor => Icons.storefront_outlined,
      Persona.carteiro => Icons.markunread_mailbox_outlined,
      Persona.idoso => Icons.elderly,
    };

/// Nome curto, para caber numa grade de 3 colunas.
String personaShortLabel(Persona p) => switch (p) {
      Persona.pedestre => 'Pedestre',
      Persona.ciclista => 'Ciclista',
      Persona.entregador => 'Entregador',
      Persona.vendedor => 'Ambulante',
      Persona.carteiro => 'Carteiro',
      Persona.idoso => 'Idoso',
    };

/// Grade 3 × 2 de perfis, todos do mesmo tamanho. O escolhido ganha o degradê
/// verde da logo.
class PersonaPicker extends StatelessWidget {
  const PersonaPicker({super.key, required this.value, required this.onChanged, this.showBenefits = false});
  final Persona value;
  final ValueChanged<Persona> onChanged;

  /// Mostra, abaixo das opções, o que muda no app para o perfil escolhido.
  final bool showBenefits;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final width = (box.maxWidth - _gap * 2) / 3;
              return Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [
                  for (final p in Persona.values)
                    SizedBox(
                      width: width,
                      child: _PersonaTile(persona: p, selected: p == value, onTap: () => onChanged(p)),
                    ),
                ],
              );
            },
          ),
          if (showBenefits) ...[
            const SizedBox(height: 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: PersonaBenefits(key: ValueKey(value), persona: value),
            ),
          ],
        ],
      );
}

class _PersonaTile extends StatelessWidget {
  const _PersonaTile({required this.persona, required this.selected, required this.onTap});
  final Persona persona;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = selected ? Colors.white : scheme.onSurfaceVariant;
    final radius = BorderRadius.circular(Tokens.radiusControl);
    return Semantics(
      button: true,
      selected: selected,
      label: persona.label,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 76,
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: selected ? Tokens.logoGradient : null,
          color: selected ? null : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ExcludeSemantics(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(personaIcon(persona), color: fg, size: 26),
                  const SizedBox(height: 6),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      personaShortLabel(persona),
                      maxLines: 1,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: fg,
                            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String _liters(int ml) => '${(ml / 1000).toStringAsFixed(1).replaceAll('.', ',')} L';

/// Três diferenciais curtos por perfil. Os números saem das mesmas regras do
/// agente (thermo_core), então nunca ficam desatualizados.
List<(IconData, String)> personaBenefits(Persona p) {
  final water = (Icons.water_drop_outlined, 'Água: ${_liters(hydrationGoalMl(p, RiskLevel.baixo))} por dia');
  final reminder = (Icons.notifications_none, 'Lembrete a cada ${hydrationReminderMinutes(RiskLevel.alto, p)} min no calor');
  const turno = (Icons.masks_outlined, 'Dicas de máscara para o turno');
  return switch (p) {
    Persona.pedestre => [(Icons.alt_route, 'Rotas Frescas a pé'), water, reminder],
    Persona.ciclista => [
        (Icons.directions_bike, 'Rotas de bicicleta'),
        (Icons.speed, 'Risco ajustado ao esforço'),
        (Icons.air, 'Alerta de fumaça: você respira 2× mais'),
      ],
    Persona.entregador => [water, (Icons.timer_outlined, 'Pausas pelo tempo ao sol'), turno],
    Persona.vendedor => [water, (Icons.beach_access_outlined, 'Avisos de pausa na sombra'), turno],
    Persona.carteiro => [(Icons.alt_route, 'Rotas Frescas entre endereços'), water, reminder],
    Persona.idoso => [
        (Icons.favorite_border, 'Avisos de calor mais cedo'),
        (Icons.health_and_safety_outlined, 'Atenção aos sinais do corpo'),
        (Icons.masks_outlined, 'Máscara já com fumaça moderada'),
      ],
  };
}

class PersonaBenefits extends StatelessWidget {
  const PersonaBenefits({super.key, required this.persona});
  final Persona persona;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'O que muda para ${personaShortLabel(persona).toLowerCase()}:',
          style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700, fontSize: (t.titleMedium?.fontSize ?? 16) + 2),
        ),
        const SizedBox(height: 12),
        for (final (icon, text) in personaBenefits(persona))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: t.bodyLarge)),
            ]),
          ),
      ],
    );
  }
}
