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
    // Próxima conquista: o desconto mais barato que ainda falta liberar.
    final locked = s.offers.where((o) => (o['cost'] as int) > s.balance && (s.isPlus || o['plusOnly'] != true)).toList()
      ..sort((a, b) => (a['cost'] as int).compareTo(b['cost'] as int));
    final goal = locked.isEmpty ? null : locked.first;

    return ListView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 32),
      children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _BalanceCard(s: s, lvl: lvl)),
        if (goal != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _GoalCard(offer: goal, balance: s.balance),
          ),
        const _Title('Ganhe gotas', subtitle: 'Toque para fazer agora'),
        _EarnGrid(rules: s.rules, multiplier: mult),
        _Title('Descontos', subtitle: s.isPlus ? 'Trocas ilimitadas' : 'Plano Grátis: $used de ${limit ?? 2} trocas este mês'),
        SizedBox(
          height: 236,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: s.offers.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) => _CouponTicket(
              offer: s.offers[i],
              balance: s.balance,
              onRedeem: () => _redeem(context, ref, s.offers[i]),
            ),
          ),
        ),
        if (demo)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
            child: Text(
              'Parceiros marcados como "Exemplo" mostram como o clube vai funcionar; esses cupons ainda não valem em lojas.',
              style: t.bodySmall?.copyWith(color: scheme.outline),
            ),
          ),
        if (s.coupons.isNotEmpty) ...[
          const _Title('Meus cupons'),
          for (final c in s.coupons)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Material(
                color: Tokens.copa.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(Tokens.radiusControl),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusControl)),
                  leading: Icon(categoryIcon(c['category'] as String?), color: Tokens.copa),
                  title: Text(c['title'] as String),
                  subtitle: Text('${c['code']} · válido até ${_date(c['expires_at'])}'),
                  trailing: const Icon(Icons.qr_code_2),
                  onTap: () => showCoupon(context, c),
                ),
              ),
            ),
        ],
        if (s.history.isNotEmpty) ...[
          const _Title('Últimas gotas'),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: _History(s: s)),
        ],
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text, {this.subtitle});
  final String text;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(text, style: t.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
        if (subtitle != null) Text(subtitle!, style: t.bodySmall),
      ]),
    );
  }
}

/// Saldo, sequência e nível.
class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.s, required this.lvl});
  final RewardsSummary s;
  final Map<String, dynamic> lvl;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Container(
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
                Text('${s.balance}', style: t.displaySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
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
            Text(s.streakDays == 1 ? 'dia seguido' : 'dias seguidos', style: t.bodySmall?.copyWith(color: Colors.white70)),
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
    );
  }
}

/// "Próxima conquista": quanto falta para o desconto mais perto.
class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.offer, required this.balance});
  final Map<String, dynamic> offer;
  final int balance;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final cost = offer['cost'] as int;
    final missing = cost - balance;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Tokens.sol.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        border: Border.all(color: Tokens.sol.withValues(alpha: 0.5)),
      ),
      child: Row(children: [
        const Icon(Icons.emoji_events_outlined, color: Tokens.sol, size: 32),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Próxima conquista', style: t.labelMedium),
            Text(offer['title'] as String, style: t.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: (balance / cost).clamp(0.0, 1.0),
                minHeight: 8,
                color: Tokens.sol,
                backgroundColor: Tokens.sol.withValues(alpha: 0.18),
              ),
            ),
            const SizedBox(height: 4),
            Text('Faltam $missing gotas', style: t.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

/// Como ganhar gotas: blocos coloridos que levam direto à ação.
class _EarnGrid extends StatelessWidget {
  const _EarnGrid({required this.rules, required this.multiplier});
  final List<Map<String, dynamic>> rules;
  final int multiplier;

  static (Color, String?) _style(String? icon) => switch (icon) {
        'today' => (Tokens.rio, null),
        'streak' => (Tokens.sol, null),
        'route' => (Tokens.copa, '/rotas'),
        'water' => (const Color(0xFF2B8FD9), '/agora'),
        'report' => (const Color(0xFF6B5BD2), '/rotas'),
        'camera' => (const Color(0xFFD9542B), '/comunidade'),
        'badge' => (const Color(0xFFC79A1E), '/comunidade'),
        _ => (Tokens.copa, null),
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final all = [
      ...rules,
      // Fotos verificadas no Social também rendem gotas.
      if (!rules.any((r) => r['icon'] == 'camera'))
        {'icon': 'camera', 'title': 'Comprovar um cuidado com foto no Social', 'points': 5},
    ];
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 16 * 2 - 10) / 2;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 10, runSpacing: 10, children: [
          ...all.map((r) {
              final (color, route) = _style(r['icon'] as String?);
              return SizedBox(
                width: w,
                child: Material(
                  borderRadius: BorderRadius.circular(Tokens.radiusBlock),
                  clipBehavior: Clip.antiAlias,
                  child: Ink(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [color, Color.lerp(color, Colors.black, 0.25)!],
                      ),
                    ),
                    child: InkWell(
                      onTap: route == null ? null : () => context.go(route),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          height: 96,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(children: [
                              Icon(_ruleIcon(r['icon'] as String?), color: Colors.white),
                              const Spacer(),
                              Text('+${(r['points'] as num).toInt() * multiplier}',
                                  style: t.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                            ]),
                            const Spacer(),
                            Text(r['title'] as String,
                                style: t.bodySmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w600),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
        ]),
      );
    });
  }
}

/// O destaque do cupom: "25%", "3 por 2", "50%".
String couponHeadline(String title) {
  final pct = RegExp(r'^(\d+)\s*%').firstMatch(title);
  if (pct != null) return '${pct.group(1)}%';
  final lp = RegExp(r'leve (\d+).*pague (\d+)', caseSensitive: false).firstMatch(title);
  if (lp != null) return '${lp.group(1)} por ${lp.group(2)}';
  if (title.toLowerCase().contains('metade')) return '50%';
  return 'Oferta';
}

/// O resto do título, sem o número: "em óculos de sol com proteção UV".
String couponItem(String title) {
  final m = RegExp(r'^\d+\s*%\s*(?:de desconto\s*)?(?:em|no|na|nos|nas|de)?\s*(.+)$', caseSensitive: false).firstMatch(title);
  final rest = m?.group(1) ?? title;
  return rest[0].toUpperCase() + rest.substring(1);
}

/// Desconto em formato de cupom: o número grande em cima, o item e o
/// parceiro embaixo, e quanto falta para trocar.
class _CouponTicket extends StatelessWidget {
  const _CouponTicket({required this.offer, required this.balance, required this.onRedeem});
  final Map<String, dynamic> offer;
  final int balance;
  final VoidCallback onRedeem;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final can = offer['canRedeem'] == true;
    final plusOnly = offer['plusOnly'] == true;
    final cost = offer['cost'] as int;
    final color = plusOnly ? Tokens.sol : Tokens.copa;
    final title = offer['title'] as String;
    final headline = couponHeadline(title);
    return SizedBox(
      width: 200,
      child: Container(
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          border: Border.all(color: color.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.black, 0.2)!]),
            ),
            child: Row(children: [
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(headline, style: t.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                ),
              ),
              Icon(categoryIcon(offer['category'] as String?), color: Colors.white),
            ]),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(headline == 'Oferta' ? title : couponItem(title),
                    style: t.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text('${offer['partner']} · ${offer['neighborhood']}',
                    style: t.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const Spacer(),
                Row(children: [
                  const Icon(Icons.water_drop, size: 16, color: Tokens.rio),
                  Text(' $cost', style: t.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      plusOnly ? 'ThermoGuia+' : (offer['demo'] == true ? 'Exemplo' : ''),
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.labelSmall?.copyWith(
                        color: plusOnly ? Tokens.sol : scheme.outline,
                        fontWeight: plusOnly ? FontWeight.w700 : null,
                      ),
                    ),
                  ),
                ]),
                const SizedBox(height: 6),
                if (can)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 36), backgroundColor: color),
                      onPressed: onRedeem,
                      child: const Text('Trocar'),
                    ),
                  )
                else
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: (balance / cost).clamp(0.0, 1.0),
                        minHeight: 6,
                        color: color,
                        backgroundColor: color.withValues(alpha: 0.15),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      offer['blockedReason'] as String? ?? 'Faltam ${cost - balance} gotas',
                      style: t.labelSmall?.copyWith(color: scheme.outline),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Últimas gotas: o total da semana, a sequência rumo ao bônus de 7 dias e
/// a lista com ícones.
class _History extends StatelessWidget {
  const _History({required this.s});
  final RewardsSummary s;

  static IconData _icon(String r) => switch (r) {
        'checkin' => Icons.today_outlined,
        'sequencia' => Icons.local_fire_department,
        'trajeto' => Icons.alt_route,
        'agua' || 'agua_comprovada' => Icons.water_drop_outlined,
        'post_verificado' => Icons.verified_outlined,
        'selo' => Icons.military_tech_outlined,
        'relato' => Icons.add_location_alt_outlined,
        'resgate' => Icons.redeem_outlined,
        _ => Icons.star_outline,
      };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final inStreak = s.streakDays % 7;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Tokens.rio.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text('+${s.weekEarned}', style: t.headlineSmall?.copyWith(color: Tokens.rio, fontWeight: FontWeight.w800)),
            const SizedBox(width: 8),
            Expanded(child: Text('gotas nos últimos 7 dias', style: t.bodyMedium)),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            for (var i = 0; i < 7; i++) ...[
              Expanded(
                child: Container(
                  height: 28,
                  decoration: BoxDecoration(
                    color: i < inStreak ? Tokens.sol : scheme.outlineVariant.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: i < inStreak ? const Icon(Icons.local_fire_department, size: 16, color: Colors.white) : null,
                ),
              ),
              if (i < 6) const SizedBox(width: 6),
            ],
          ]),
          const SizedBox(height: 6),
          Text(
            'Mais ${7 - inStreak} ${7 - inStreak == 1 ? 'dia' : 'dias'} seguidos abrindo o app = +20 gotas de bônus',
            style: t.bodySmall,
          ),
        ]),
      ),
      const SizedBox(height: 8),
      for (final h in s.history.take(8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: ((h['points'] as int) > 0 ? Tokens.copa : scheme.error).withValues(alpha: 0.12),
              child: Icon(_icon(h['reason'] as String), size: 18, color: (h['points'] as int) > 0 ? Tokens.copa : scheme.error),
            ),
            const SizedBox(width: 12),
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
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ]),
        ),
    ]);
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
