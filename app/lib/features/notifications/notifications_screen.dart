import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/services/notification_inbox.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';

/// Sino da tela Agora: as notificações que o app mostrou, mais novas primeiro.
class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  // Lidas ao sair, para a pessoa ainda ver quais eram novas.
  late final _inbox = ref.read(notificationInboxProvider);

  @override
  void dispose() {
    _inbox.markAllRead();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(notificationInboxProvider);
    final items = inbox.items;
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        actions: [
          IconButton(
            tooltip: 'Configurar notificações',
            icon: const Icon(Icons.tune),
            onPressed: () => context.push('/configuracoes'),
          ),
          if (items.isNotEmpty)
            TextButton(onPressed: () => inbox.clear(), child: const Text('Limpar')),
        ],
      ),
      body: items.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.notifications_none, size: 56, color: Theme.of(context).colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('Nenhuma notificação por enquanto', style: t.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Avisos de fumaça, calor, água e o resumo do dia aparecem aqui.',
                    style: t.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                ]),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
              itemBuilder: (_, i) => _Tile(item: items[i]),
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.item});
  final InboxItem item;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (icon, color) = switch (item.kind) {
      NotifKind.ar => (Icons.air, const Color(0xFFD9542B)),
      NotifKind.calor => (Icons.thermostat, Tokens.sol),
      NotifKind.agua => (Icons.water_drop_outlined, Tokens.rio),
      NotifKind.dia => (Icons.wb_twilight_outlined, Tokens.copa),
    };
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: CircleAvatar(backgroundColor: color.withValues(alpha: 0.14), child: Icon(icon, color: color)),
      title: Text(item.title, style: t.titleSmall?.copyWith(fontWeight: item.read ? FontWeight.w500 : FontWeight.w800)),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('${item.body}\n${_when(item.at)}', style: t.bodyMedium),
      ),
      isThreeLine: true,
      trailing: item.read
          ? null
          : Container(width: 10, height: 10, decoration: const BoxDecoration(color: Tokens.sol, shape: BoxShape.circle)),
      onTap: item.route == null ? null : () => context.go(item.route!),
    );
  }

  String _when(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final diff = today.difference(day).inDays;
    final label = diff == 0 ? 'Hoje' : diff == 1 ? 'Ontem' : '${at.day.toString().padLeft(2, '0')}/${at.month.toString().padLeft(2, '0')}';
    return '$label, ${hm(at)}';
  }
}
