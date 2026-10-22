import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import 'profile_screen.dart';

/// Chave Pix das doações, definida na compilação:
///   flutter build apk --dart-define=PIX_KEY=sua-chave
/// Sem chave, o botão só registra o interesse da pessoa.
const _pixKey = String.fromEnvironment('PIX_KEY');
const _pixName = String.fromEnvironment('PIX_NAME', defaultValue: 'ThermoGuia Manaus');

class DonationTier {
  const DonationTier(this.reais, this.icon, this.impact);
  final int reais;
  final IconData icon;

  /// Completa a frase "Com R$ X você ...".
  final String impact;

  String get label => 'R\$ $reais';
}

/// Valores sugeridos e o que cada um ajuda a fazer na cidade. Ajuste aqui
/// conforme os custos reais (muda nativa com plantio, máscara de proteção).
const donationTiers = [
  DonationTier(10, Icons.notifications_active_outlined,
      'ajuda a manter os alertas de calor e fumaça no celular de 100 pessoas por um mês'),
  DonationTier(25, Icons.masks_outlined,
      'ajuda a entregar máscaras de proteção para 5 pessoas nos dias de fumaça: menos gente respirando fumaça em Manaus'),
  DonationTier(50, Icons.park_outlined,
      'ajuda a plantar 3 árvores nativas em Manaus: mais sombra nas calçadas e menos calor'),
  DonationTier(100, Icons.forest_outlined,
      'ajuda a plantar 6 árvores e entregar máscaras para 4 pessoas: mais sombra e menos fumaça no pulmão de quem trabalha na rua'),
];

/// Apoie o ThermoGuia: o app é gratuito e as doações viram árvores,
/// máscaras e alertas para a cidade.
class DonateScreen extends ConsumerStatefulWidget {
  const DonateScreen({super.key});

  @override
  ConsumerState<DonateScreen> createState() => _DonateScreenState();
}

class _DonateScreenState extends ConsumerState<DonateScreen> {
  DonationTier _tier = donationTiers[2];

  Future<void> _donate() async {
    // O registro sincroniza em segundo plano: a resposta ao toque é imediata.
    unawaited(logPlanInterest(ref, 'doacao_${_tier.reais}'));
    if (_pixKey.isEmpty) {
      showMessage(context, 'Obrigado! As doações abrem em breve e avisaremos você.');
      return;
    }
    await showModalBottomSheet<void>(context: context, builder: (_) => _PixSheet(tier: _tier));
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Apoie o ThermoGuia')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('Ajude Manaus a respirar melhor', style: t.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'O ThermoGuia é gratuito para todos. Com uma doação, você ajuda a manter o app no ar '
            'e a levar sombra e proteção contra a fumaça para quem mais precisa.',
            style: t.bodyLarge,
          ),
          const SizedBox(height: 16),
          for (final tier in donationTiers)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TierCard(tier: tier, selected: tier == _tier, onTap: () => setState(() => _tier = tier)),
            ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Tokens.copa.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(Tokens.radiusBlock),
              border: Border.all(color: Tokens.copa, width: 2),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Com ${_tier.label} você ${_tier.impact}.', style: t.titleMedium),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: Text('Doar ${_tier.label}'),
                  onPressed: _donate,
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          Text('Para onde vai a sua doação', style: t.titleMedium),
          const SizedBox(height: 8),
          for (final (icon, text) in const [
            (Icons.park_outlined, 'Árvores nativas plantadas nas ruas mais quentes, onde falta sombra.'),
            (Icons.masks_outlined, 'Máscaras de proteção para trabalhadores de rua nos dias de fumaça.'),
            (Icons.notifications_active_outlined, 'Alertas de calor, fumaça e chuva no celular de quem usa o app.'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 22, color: Tokens.copa),
                const SizedBox(width: 10),
                Expanded(child: Text(text, style: t.bodyMedium)),
              ]),
            ),
          const SizedBox(height: 12),
          Text(
            'Doação voluntária e única. Nenhuma função de proteção do app depende dela.',
            style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TierCard extends StatelessWidget {
  const _TierCard({required this.tier, required this.selected, required this.onTap});
  final DonationTier tier;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected ? Tokens.copa.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: InkWell(
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
              border: Border.all(color: selected ? Tokens.copa : scheme.outlineVariant, width: selected ? 2 : 1),
            ),
            child: Row(children: [
              Icon(tier.icon, color: Tokens.copa, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(tier.label, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  Text('Você ${tier.impact}.', style: t.bodyMedium),
                ]),
              ),
              Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off,
                  color: selected ? Tokens.copa : scheme.outline),
            ]),
          ),
        ),
      ),
    );
  }
}

class _PixSheet extends StatelessWidget {
  const _PixSheet({required this.tier});
  final DonationTier tier;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Doar ${tier.label} com Pix', style: t.titleLarge),
          const SizedBox(height: 8),
          Text('No app do seu banco, escolha Pix, cole a chave abaixo e digite ${tier.label}.', style: t.bodyMedium),
          const SizedBox(height: 12),
          SelectableText(_pixKey, style: t.titleMedium),
          Text('Favorecido: $_pixName', style: t.bodySmall),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: const Icon(Icons.copy),
            label: const Text('Copiar chave Pix'),
            onPressed: () async {
              await Clipboard.setData(const ClipboardData(text: _pixKey));
              if (context.mounted) {
                Navigator.pop(context);
                showMessage(context, 'Chave Pix copiada. Obrigado por apoiar o ThermoGuia!');
              }
            },
          ),
        ]),
      ),
    );
  }
}
