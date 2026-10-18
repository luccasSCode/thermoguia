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

/// Resumo de cada plano quando o servidor ainda não manda `highlights`
/// (versões antigas da API).
const _fallbackHighlights = {
  'free': ['Risco de calor e alertas de fumaça', 'Rotas Frescas sem limite', 'Lembretes de água e botão de emergência'],
  'plus': ['Assistente sem limite de perguntas', 'Gotas em dobro e cupons de até 25%', 'Família, relógio e mapas offline'],
  'empresas': ['Painel de calor e fumaça da equipe', 'Pausas automáticas e alerta ao supervisor', 'Relatórios para NR-15 e NR-21'],
};

List<String> _highlights(Map plan) =>
    (plan['highlights'] as List?)?.cast<String>() ?? _fallbackHighlights[plan['id']] ?? const [];

/// Planos: o que protege a saúde é sempre grátis; o ThermoGuia+ tira os
/// limites. Cada plano aparece em três linhas; a comparação completa fica
/// recolhida. O catálogo vem do servidor; o pagamento será integrado às lojas
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
    final features = (c['features'] as List).cast<Map>();
    final business = (c['business'] as Map?)?.cast<String, dynamic>();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Text('Escolha seu plano', style: t.headlineSmall),
        const SizedBox(height: 4),
        Text('O que protege sua saúde é sempre grátis.', style: t.bodyLarge),
        if (plus['priceYear'] != null) ...[
          const SizedBox(height: 16),
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
        ],
        const SizedBox(height: 16),
        _PlanCard(
          name: free['name'] as String,
          price: free['price'] as String,
          tagline: free['tagline'] as String?,
          highlights: _highlights(free),
          badge: isPlus ? null : 'Seu plano',
        ),
        const SizedBox(height: 12),
        _PlanCard(
          name: plus['name'] as String,
          price: (_yearly ? plus['priceYear'] : plus['price']) as String,
          note: _yearly ? plus['yearNote'] as String? : null,
          tagline: plus['tagline'] as String?,
          highlights: _highlights(plus),
          badge: isPlus ? 'Seu plano' : 'Recomendado',
          highlight: true,
          action: FilledButton(
            onPressed: isPlus ? null : () => _interest('plus'),
            child: Text(isPlus ? 'Você já é ThermoGuia+' : 'Quero o ThermoGuia+'),
          ),
        ),
        if (business != null) ...[
          const SizedBox(height: 12),
          _PlanCard(
            name: business['name'] as String,
            price: business['price'] as String,
            tagline: business['tagline'] as String? ?? 'Para equipes que trabalham na rua',
            highlights: _highlights(business),
            action: OutlinedButton(
              onPressed: () => _interest(business['id'] as String),
              child: const Text('Falar com a equipe'),
            ),
          ),
        ],
        const SizedBox(height: 12),
        _Comparison(features: features, plusName: plus['name'] as String),
        const SizedBox(height: 12),
        Text(
          'A assinatura será feita pela App Store ou Google Play e pode ser cancelada quando quiser.',
          style: t.bodySmall,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.name,
    required this.price,
    required this.highlights,
    this.tagline,
    this.note,
    this.badge,
    this.highlight = false,
    this.action,
  });
  final String name;
  final String price;
  final List<String> highlights;
  final String? tagline;
  final String? note;
  final String? badge;
  final bool highlight;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: highlight ? Tokens.sol.withValues(alpha: 0.10) : scheme.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        border: Border.all(color: highlight ? Tokens.sol : scheme.outlineVariant, width: highlight ? 2 : 1),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: t.titleMedium),
              if (tagline != null) Text(tagline!, style: t.bodySmall),
            ]),
          ),
          if (badge != null)
            Container(
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
        ]),
        const SizedBox(height: 8),
        Text(price, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
        if (note != null) Text(note!, style: t.bodySmall),
        const SizedBox(height: 10),
        for (final h in highlights)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.check, size: 20, color: highlight ? Tokens.sol : Tokens.copa),
              const SizedBox(width: 8),
              Expanded(child: Text(h, style: t.bodyMedium)),
            ]),
          ),
        if (action != null) ...[
          const SizedBox(height: 6),
          SizedBox(width: double.infinity, child: action!),
        ],
      ]),
    );
  }
}

/// Comparação recurso a recurso, recolhida por padrão para não poluir a tela.
class _Comparison extends StatelessWidget {
  const _Comparison({required this.features, required this.plusName});
  final List<Map> features;
  final String plusName;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      // Sem as linhas divisórias que o ExpansionTile desenha ao abrir.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.symmetric(horizontal: 4),
        title: Text('Comparar todos os recursos', style: t.titleSmall),
        children: [
          for (final f in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  '${f['title']}${f['soon'] == true ? ' (em breve)' : ''}',
                  style: t.titleSmall,
                ),
                const SizedBox(height: 2),
                Text('Grátis: ${f['free']}', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                Text('$plusName: ${f['plus']}', style: t.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
    );
  }
}
