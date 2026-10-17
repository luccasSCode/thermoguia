import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/thermo_loader.dart';
import '../session/presentation/session_controller.dart';
import 'profile_screen.dart';

final _catalogProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final data = await ref.read(apiClientProvider).get('/plans/compare') as Map;
  return data.cast<String, dynamic>();
});

IconData _icon(String? key) => switch (key) {
      'club' => Icons.redeem_outlined,
      'watch' => Icons.watch_outlined,
      'chat' => Icons.forum_outlined,
      'health' => Icons.monitor_heart_outlined,
      'alarm' => Icons.notifications_active_outlined,
      'family' => Icons.family_restroom,
      'stops' => Icons.alt_route,
      'offline' => Icons.download_for_offline_outlined,
      'place' => Icons.bookmark_outline,
      'calendar' => Icons.event_available_outlined,
      'widgets' => Icons.widgets_outlined,
      'report' => Icons.insights_outlined,
      'thermostat' => Icons.thermostat,
      'navigation' => Icons.navigation_outlined,
      'water' => Icons.water_drop_outlined,
      'emergency' => Icons.emergency_outlined,
      'sun' => Icons.wb_sunny_outlined,
      _ => Icons.check_circle_outline,
    };

/// Planos: o que protege a saúde é sempre grátis; o ThermoGuia+ tira os
/// limites. O catálogo vem do servidor; o pagamento será integrado às lojas
/// (Google Play Billing / App Store) numa próxima fase.
class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  bool _yearly = false;

  Future<void> _interest(String plan) async {
    await logPlanInterest(ref, plan);
    if (mounted) showMessage(context, 'Anotado! Avisaremos você quando estiver disponível.');
  }

  @override
  Widget build(BuildContext context) {
    final catalog = ref.watch(_catalogProvider);
    final isPlus = ref.watch(sessionProvider.select((s) => s.user?.isPlus ?? false));
    return Scaffold(
      appBar: AppBar(title: const Text('Planos')),
      body: catalog.when(
        loading: () => const Center(child: ThermoLoader()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_catalogProvider)),
        data: (c) => _content(context, c, isPlus),
      ),
    );
  }

  Widget _content(BuildContext context, Map<String, dynamic> c, bool isPlus) {
    final t = Theme.of(context).textTheme;
    final plans = (c['plans'] as List).cast<Map>();
    final free = plans.firstWhere((p) => p['id'] == 'free');
    final plus = plans.firstWhere((p) => p['id'] == 'plus');
    final always = (c['alwaysFree'] as List).cast<Map>();
    final features = (c['features'] as List).cast<Map>();
    final business = (c['business'] as Map?)?.cast<String, dynamic>();
    final hasSoon = features.any((f) => f['soon'] == true);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text('Escolha como usar o ThermoGuia', style: t.headlineSmall),
        const SizedBox(height: 6),
        Text('O que protege sua saúde é sempre grátis. O ThermoGuia+ tira os limites.', style: t.bodyLarge),
        const SizedBox(height: 16),
        if (plus['priceYear'] != null)
          Center(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Mensal')),
                ButtonSegment(value: true, label: Text('Anual')),
              ],
              selected: {_yearly},
              onSelectionChanged: (v) => setState(() => _yearly = v.first),
            ),
          ),
        const SizedBox(height: 14),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: _PlanCard(
                name: free['name'] as String,
                price: free['price'] as String,
                tagline: free['tagline'] as String? ?? '',
                badge: isPlus ? null : 'Seu plano',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _PlanCard(
                name: plus['name'] as String,
                price: (_yearly ? plus['priceYear'] : plus['price']) as String,
                note: _yearly ? plus['yearNote'] as String? : null,
                tagline: plus['tagline'] as String? ?? '',
                badge: isPlus ? 'Seu plano' : 'Recomendado',
                highlight: true,
              ),
            ),
          ]),
        ),
        const SectionTitle('Sempre grátis, sem limite'),
        _AlwaysFree(items: always),
        const SectionTitle('Grátis × ThermoGuia+'),
        for (final f in features) _FeatureRow(feature: f, plusName: plus['name'] as String),
        const SizedBox(height: 16),
        FilledButton.icon(
          icon: const Icon(Icons.workspace_premium_outlined),
          onPressed: isPlus ? null : () => _interest('plus'),
          label: Text(isPlus ? 'Você já é ThermoGuia+' : 'Quero o ThermoGuia+'),
        ),
        const SizedBox(height: 8),
        Text(
          [
            if (hasSoon) 'Os recursos marcados "Em breve" serão lançados nas próximas versões.',
            'A assinatura será feita pela App Store ou Google Play e pode ser cancelada quando quiser.',
          ].join(' '),
          style: t.bodySmall,
          textAlign: TextAlign.center,
        ),
        if (business != null) ...[
          const SizedBox(height: 24),
          _BusinessCard(business: business, onContact: () => _interest(business['id'] as String)),
        ],
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.tagline,
    this.note,
    this.badge,
    this.highlight = false,
  });
  final String name;
  final String price;
  final String tagline;
  final String? note;
  final String? badge;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: highlight ? Tokens.sol.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        border: Border.all(color: highlight ? Tokens.sol : scheme.outlineVariant, width: highlight ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (badge != null)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: highlight ? Tokens.sol : scheme.secondaryContainer,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(badge!,
                style: t.labelSmall?.copyWith(
                  color: highlight ? Colors.white : scheme.onSecondaryContainer,
                  fontWeight: FontWeight.w700,
                )),
          ),
        Text(name, style: t.titleMedium),
        const SizedBox(height: 4),
        Text(price, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (note != null) Text(note!, style: t.bodySmall),
        const SizedBox(height: 8),
        Text(tagline, style: t.bodySmall),
      ]),
    );
  }
}

class _AlwaysFree extends StatelessWidget {
  const _AlwaysFree({required this.items});
  final List<Map> items;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      decoration: BoxDecoration(
        color: Tokens.copa.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        border: Border.all(color: Tokens.copa.withValues(alpha: 0.4)),
      ),
      child: Column(children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Icon(_icon(i['icon'] as String?), color: Tokens.copa, size: 22),
              const SizedBox(width: 12),
              Expanded(child: Text(i['title'] as String, style: t.bodyMedium)),
            ]),
          ),
      ]),
    );
  }
}

/// Um recurso, lado a lado: o que o Grátis tem e o que o ThermoGuia+ libera.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.feature, required this.plusName});
  final Map feature;
  final String plusName;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final soon = feature['soon'] == true;
    final detail = feature['detail'] as String?;

    Widget cell(String label, String value, {bool plus = false}) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: plus ? Tokens.sol.withValues(alpha: 0.10) : scheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
              border: plus ? Border.all(color: Tokens.sol.withValues(alpha: 0.5)) : null,
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: t.labelSmall?.copyWith(color: plus ? Tokens.sol : scheme.outline)),
              const SizedBox(height: 2),
              Text(value, style: t.bodySmall?.copyWith(fontWeight: plus ? FontWeight.w700 : null)),
            ]),
          ),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(_icon(feature['icon'] as String?), color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text(feature['title'] as String, style: t.titleSmall)),
          if (soon)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outline),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('Em breve', style: t.labelSmall),
            ),
        ]),
        if (detail != null)
          Padding(
            padding: const EdgeInsets.only(left: 34, top: 2),
            child: Text(detail, style: t.bodySmall),
          ),
        const SizedBox(height: 8),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            cell('Grátis', feature['free'] as String),
            const SizedBox(width: 8),
            cell(plusName, feature['plus'] as String, plus: true),
          ]),
        ),
      ]),
    );
  }
}

class _BusinessCard extends StatelessWidget {
  const _BusinessCard({required this.business, required this.onContact});
  final Map<String, dynamic> business;
  final VoidCallback onContact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.apartment_outlined),
          const SizedBox(width: 10),
          Expanded(child: Text(business['name'] as String, style: t.titleMedium)),
          Text(business['price'] as String, style: t.bodyMedium),
        ]),
        const SizedBox(height: 4),
        Text('Para empresas com equipes que trabalham na rua.', style: t.bodySmall),
        const SizedBox(height: 10),
        for (final f in (business['features'] as List).cast<String>())
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check, size: 20, color: Tokens.copa),
              const SizedBox(width: 8),
              Expanded(child: Text(f, style: t.bodyMedium)),
            ]),
          ),
        const SizedBox(height: 6),
        OutlinedButton(onPressed: onContact, child: const Text('Falar com a equipe')),
      ]),
    );
  }
}
