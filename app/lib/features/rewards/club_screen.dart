import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/thermo_loader.dart';
import 'rewards_controller.dart';

IconData categoryIcon(String? c) => switch (c) {
      'acai' => Icons.icecream_outlined,
      'coco' => Icons.local_drink_outlined,
      'mercado' => Icons.shopping_cart_outlined,
      'cafe' => Icons.local_cafe_outlined,
      'esporte' => Icons.sports_handball_outlined,
      'farmacia' => Icons.local_pharmacy_outlined,
      'bike' => Icons.pedal_bike,
      'otica' => Icons.visibility_outlined,
      _ => Icons.storefront_outlined,
    };

IconData _ruleIcon(String? k) => switch (k) {
      'today' => Icons.today_outlined,
      'streak' => Icons.local_fire_department_outlined,
      'route' => Icons.alt_route,
      'water' => Icons.water_drop_outlined,
      'report' => Icons.add_location_alt_outlined,
      'camera' => Icons.add_a_photo_outlined,
      'badge' => Icons.military_tech_outlined,
      _ => Icons.star_outline,
    };

String _reasonLabel(String r) => switch (r) {
      'checkin' => 'Abriu o app',
      'sequencia' => 'Bônus de sequência',
      'trajeto' => 'Rota Fresca concluída',
      'agua' => 'Meta de água do dia',
      'agua_comprovada' => 'Água comprovada com foto',
      'post_verificado' => 'Publicação verificada',
      'selo' => 'Selo da semana',
      'relato' => 'Relato no mapa',
      'resgate' => 'Troca por desconto',
      _ => 'Ajuste',
    };

String _date(Object? v) {
  final d = DateTime.tryParse('$v')?.toLocal();
  return d == null ? '' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
}

/// Clube H2O: gotas ganhas cuidando de si no calor, trocadas por
/// descontos em parceiros.
class ClubScreen extends ConsumerWidget {
  const ClubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(rewardsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Clube H2O')),
      body: data.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: ThermoLoader()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.read(rewardsProvider.notifier).refresh()),
        data: (s) => RefreshIndicator(
          onRefresh: () => ref.read(rewardsProvider.notifier).refresh(),
          child: _Body(s: s),
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.s});
  final RewardsSummary s;

  Future<void> _redeem(BuildContext context, WidgetRef ref, Map<String, dynamic> o) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(o['title'] as String),
        content: Text('Trocar ${o['cost']} gotas por este desconto em ${o['partner']}? '
            'O cupom vale por 7 dias.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Agora não')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Trocar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final c = await ref.read(rewardsProvider.notifier).redeem(o['id'] as String);
      if (context.mounted) await showCoupon(context, {...o, ...c});
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final lvl = s.level;
    final plan = s.plan;
    final limit = plan['monthlyLimit'] as int?;
    final used = plan['redeemsThisMonth'] as int? ?? 0;
    final demo = s.offers.any((o) => o['demo'] == true);
    final mult = (plan['multiplier'] as num?)?.toInt() ?? 1;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Saldo, nível e sequência.
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Tokens.rioProfundo, Tokens.rio]),
            borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              // Encolhe em vez de estourar com letras grandes (acessibilidade).
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(children: [
                    const Icon(Icons.water_drop, color: Colors.white, size: 34),
                    const SizedBox(width: 10),
                    Text('${s.balance}',
                        style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(width: 6),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text('gotas', style: t.titleMedium?.copyWith(color: Colors.white)),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(children: [
                  const Icon(Icons.local_fire_department, color: Tokens.sol),
                  Text(' ${s.streakDays}', style: t.titleLarge?.copyWith(color: Colors.white)),
                ]),
                Text(s.streakDays == 1 ? 'dia seguido' : 'dias seguidos',
                    style: t.bodySmall?.copyWith(color: Colors.white70)),
              ]),
            ]),
            const SizedBox(height: 14),
            Text('Nível ${lvl['name']}', style: t.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (lvl['progress'] as num).toDouble(),
                minHeight: 8,
                color: Tokens.sol,
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              lvl['next'] == null ? 'Você chegou ao nível máximo!' : 'Faltam ${lvl['toNext']} gotas para ${lvl['next']}',
              style: t.bodySmall?.copyWith(color: Colors.white70),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // Plano.
        Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
          decoration: BoxDecoration(
            color: s.isPlus ? Tokens.sol.withValues(alpha: 0.12) : scheme.surface,
            borderRadius: BorderRadius.circular(Tokens.radiusControl),
            border: Border.all(color: s.isPlus ? Tokens.sol : scheme.outlineVariant),
          ),
          child: Row(children: [
            Icon(Icons.workspace_premium_outlined, color: s.isPlus ? Tokens.sol : scheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                s.isPlus
                    ? 'ThermoGuia+: gotas em dobro, trocas ilimitadas e descontos exclusivos.'
                    : 'Plano Grátis: $used de ${limit ?? 2} trocas usadas este mês.',
                style: t.bodyMedium,
              ),
            ),
            if (!s.isPlus)
              TextButton(onPressed: () => context.push('/planos'), child: const Text('Gotas em dobro')),
          ]),
        ),
        if (demo) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Os parceiros marcados como "Exemplo" mostram como o clube vai funcionar. '
                  'Os cupons deles ainda não valem em lojas.',
                  style: t.bodySmall,
                ),
              ),
            ]),
          ),
        ],
        if (s.coupons.isNotEmpty) ...[
          const SectionTitle('Meus cupons'),
          for (final c in s.coupons)
            Card(
              child: ListTile(
                leading: Icon(categoryIcon(c['category'] as String?), color: Tokens.copa),
                title: Text(c['title'] as String),
                subtitle: Text('${c['code']} · válido até ${_date(c['expires_at'])}'),
                trailing: const Icon(Icons.qr_code_2),
                onTap: () => showCoupon(context, c),
              ),
            ),
        ],
        const SectionTitle('Troque suas gotas'),
        for (final o in s.offers) _OfferCard(offer: o, onRedeem: () => _redeem(context, ref, o)),
        const SectionTitle('Como ganhar gotas'),
        for (final r in s.rules)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Tokens.rio.withValues(alpha: 0.12),
              child: Icon(_ruleIcon(r['icon'] as String?), color: Tokens.rio),
            ),
            title: Text(r['title'] as String),
            trailing: Text('+${(r['points'] as num).toInt() * mult}',
                style: t.titleMedium?.copyWith(color: Tokens.copa, fontWeight: FontWeight.w800)),
          ),
        if (s.history.isNotEmpty) ...[
          const SectionTitle('Últimas gotas'),
          for (final h in s.history.take(10))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                Expanded(child: Text(_reasonLabel(h['reason'] as String), style: t.bodyMedium)),
                Text(_date(h['created_at']), style: t.bodySmall),
                const SizedBox(width: 12),
                SizedBox(
                  width: 52,
                  child: Text(
                    '${(h['points'] as int) > 0 ? '+' : ''}${h['points']}',
                    textAlign: TextAlign.right,
                    style: t.titleSmall?.copyWith(
                      color: (h['points'] as int) > 0 ? Tokens.copa : scheme.error,
                    ),
                  ),
                ),
              ]),
            ),
        ],
      ],
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer, required this.onRedeem});
  final Map<String, dynamic> offer;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final can = offer['canRedeem'] == true;
    final plusOnly = offer['plusOnly'] == true;
    Widget tag(String text, Color c) => Container(
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(border: Border.all(color: c), borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: t.labelSmall?.copyWith(color: c)),
        );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          border: Border.all(color: plusOnly ? Tokens.sol.withValues(alpha: 0.6) : scheme.outlineVariant),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: (plusOnly ? Tokens.sol : Tokens.copa).withValues(alpha: 0.14),
            child: Icon(categoryIcon(offer['category'] as String?), color: plusOnly ? Tokens.sol : Tokens.copa),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(offer['title'] as String, style: t.titleSmall),
              const SizedBox(height: 2),
              Text('${offer['partner']} · ${offer['neighborhood']}', style: t.bodySmall),
              const SizedBox(height: 6),
              Wrap(children: [
                if (plusOnly) tag('ThermoGuia+', Tokens.sol),
                if (offer['demo'] == true) tag('Exemplo', scheme.outline),
              ]),
              if (!can && offer['blockedReason'] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(offer['blockedReason'] as String, style: t.bodySmall?.copyWith(color: scheme.outline)),
                ),
            ]),
          ),
          const SizedBox(width: 8),
          Column(children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.water_drop, size: 16, color: Tokens.rio),
              Text(' ${offer['cost']}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            ]),
            const SizedBox(height: 6),
            FilledButton.tonal(
              style: FilledButton.styleFrom(minimumSize: const Size(80, 38), padding: const EdgeInsets.symmetric(horizontal: 12)),
              onPressed: can ? onRedeem : null,
              child: const Text('Trocar'),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Cupom para mostrar no caixa.
Future<void> showCoupon(BuildContext context, Map<String, dynamic> c) => showModalBottomSheet<void>(
      context: context,
      builder: (ctx) {
        final t = Theme.of(ctx).textTheme;
        final demo = c['demo'] == true || '${c['code']}'.startsWith('EXEMPLO');
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(categoryIcon(c['category'] as String?), size: 40, color: Tokens.copa),
              const SizedBox(height: 8),
              Text(c['title'] as String, style: t.titleLarge, textAlign: TextAlign.center),
              Text('${c['partner']}', style: t.bodyMedium),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border.all(color: Tokens.copa, width: 2),
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                ),
                child: SelectableText(
                  '${c['code']}',
                  textAlign: TextAlign.center,
                  style: t.headlineSmall?.copyWith(fontWeight: FontWeight.w800, letterSpacing: 2),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                demo
                    ? 'Cupom de exemplo: mostra como vai funcionar, mas ainda não vale em lojas.'
                    : 'Mostre este código no caixa. Válido até ${_date(c['expires_at'])}.',
                style: t.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                icon: const Icon(Icons.copy),
                label: const Text('Copiar código'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: '${c['code']}'));
                  Navigator.pop(ctx);
                  showMessage(context, 'Código copiado.');
                },
              ),
            ]),
          ),
        );
      },
    );
