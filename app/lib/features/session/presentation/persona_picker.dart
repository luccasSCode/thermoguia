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
  const PersonaPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.showBenefits = false,
    this.compact = false,
  });
  final Persona value;
  final ValueChanged<Persona> onChanged;

  /// Mostra, abaixo das opções, o que muda no app para o perfil escolhido.
  final bool showBenefits;

  /// Versão mais baixa, para caber numa tela sem rolar.
  final bool compact;

  static const _gap = 10.0;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var row = 0; row < Persona.values.length; row += 3) ...[
            if (row > 0) const SizedBox(height: _gap),
            Row(children: [
              for (final p in Persona.values.skip(row).take(3)) ...[
                if (p != Persona.values[row]) const SizedBox(width: _gap),
                Expanded(
                  child: _PersonaTile(persona: p, selected: p == value, compact: compact, onTap: () => onChanged(p)),
                ),
              ],
            ]),
          ],
          if (showBenefits) ...[
            SizedBox(height: compact ? 12 : 20),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: PersonaBenefits(key: ValueKey(value), persona: value, compact: compact),
            ),
          ],
        ],
      );
}

class _PersonaTile extends StatelessWidget {
  const _PersonaTile({required this.persona, required this.selected, required this.compact, required this.onTap});
  final Persona persona;
  final bool selected;
  final bool compact;
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
        height: compact ? 64 : 76,
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
                  Icon(personaIcon(persona), color: fg, size: compact ? 24 : 26),
                  SizedBox(height: compact ? 4 : 6),
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
    Persona.pedestre => [(Icons.alt_route, 'Rotas Frescas a pé'), water, (Icons.air, 'Alertas de fumaça e Hora Segura')],
    Persona.ciclista => [
        (Icons.directions_bike, 'Rotas de bicicleta'),
        (Icons.speed, 'Risco ajustado ao esforço'),
        (Icons.air, 'Alerta de fumaça: você respira 2× mais'),
      ],
    Persona.entregador => [water, (Icons.timer_outlined, 'Pausas pelo tempo ao sol'), turno],
    Persona.vendedor => [water, (Icons.beach_access_outlined, 'Avisos de pausa na sombra'), turno],
    Persona.carteiro => [(Icons.alt_route, 'Rotas Frescas entre endereços'), water, reminder],
    Persona.idoso => [
        (Icons.family_restroom, 'Responsável acompanha sua água em tempo real'),
        (Icons.notification_important_outlined, 'Ele recebe alerta se você tocar em "Estou passando mal"'),
        (Icons.favorite_border, 'Avisos de calor e fumaça mais cedo'),
      ],
  };
}

class PersonaBenefits extends StatelessWidget {
  const PersonaBenefits({super.key, required this.persona, this.compact = false});
  final Persona persona;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'O que muda para ${personaShortLabel(persona).toLowerCase()}:',
          style: t.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: (t.titleMedium?.fontSize ?? 16) + (compact ? 0 : 2),
          ),
        ),
        SizedBox(height: compact ? 8 : 12),
        for (final (icon, text) in personaBenefits(persona))
          Padding(
            padding: EdgeInsets.only(bottom: compact ? 6 : 10),
            child: Row(children: [
              Icon(icon, size: 20, color: scheme.primary),
              const SizedBox(width: 12),
              Expanded(child: Text(text, style: compact ? t.bodyMedium : t.bodyLarge)),
            ]),
          ),
      ],
    );
  }
}
