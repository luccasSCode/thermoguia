import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/services/notification_inbox.dart';
import '../../core/widgets/common.dart';
import '../air/air_providers.dart';
import '../notifications/engagement.dart';
import 'app_icon_setting.dart';

/// Configurações: o que o app pode avisar, o histórico de decisões e, no
/// Android, o ícone do app.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Future<void> _toggle(NotifKind k, bool on) async {
    if (k == NotifKind.ar) {
      // Também refaz os avisos de fumaça programados.
      await ref.read(airAlertsSettingProvider.notifier).set(on);
    } else {
      await ref.read(notificationServiceProvider).setEnabled(k, on);
      if (k == NotifKind.dia) await ref.read(engagementSchedulerProvider)();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final svc = ref.watch(notificationServiceProvider);
    final daily = ref.watch(engagementSettingsProvider);
    ref.watch(airAlertsSettingProvider);
    final dayOn = svc.enabled(NotifKind.dia);

    return Scaffold(
      appBar: AppBar(title: const Text('Configurações')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          const SectionTitle('Notificações'),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Escolha o que o ThermoGuia pode avisar no seu celular.', style: t.bodyMedium),
          ),
          for (final k in NotifKind.values)
            SwitchListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              secondary: Icon(_icon(k)),
              title: Text(k.title),
              subtitle: Text(k.subtitle),
              value: svc.enabled(k),
              onChanged: (on) => _toggle(k, on),
            ),
          if (dayOn)
            Padding(
              padding: const EdgeInsets.only(left: 36),
              child: Column(children: [
                for (final e in Engagement.values)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.only(left: 20, right: 12),
                    title: Text(e.title),
                    subtitle: Text(e.when),
                    value: daily.contains(e),
                    onChanged: (on) => ref.read(engagementSettingsProvider.notifier).toggle(e, on ?? false),
                  ),
              ]),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Text(
              'O resumo do dia nunca chega entre 19h30 e 6h30 (no máximo 4 por dia). Os alertas de fumaça '
              'são urgentes e podem chegar das 6h às 22h. Som e vibração de cada tipo podem ser ajustados '
              'nos ajustes de notificação do celular.',
              style: t.bodySmall,
            ),
          ),
          const SectionTitle('Privacidade'),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.history),
            title: const Text('Histórico de decisões'),
            subtitle: const Text('Tudo o que você aprovou ou recusou'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/historico'),
          ),
          if (canChooseAppIcon) ...[
            const SectionTitle('Ícone do app'),
            const AppIconPicker(),
          ],
        ],
      ),
    );
  }

  IconData _icon(NotifKind k) => switch (k) {
        NotifKind.agua => Icons.water_drop_outlined,
        NotifKind.calor => Icons.thermostat,
        NotifKind.ar => Icons.air,
        NotifKind.dia => Icons.wb_twilight_outlined,
      };
}
