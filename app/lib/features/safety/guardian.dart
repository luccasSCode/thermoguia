import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../session/presentation/session_controller.dart';
import 'safety_repository.dart';

/// Link de acompanhamento do responsável (null = desativado).
class GuardianController extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => (await ref.read(apiClientProvider).get('/guardian/link') as Map)['url'] as String?;

  Future<String> enable() async {
    final url = (await ref.read(apiClientProvider).post('/guardian/link') as Map)['url'] as String;
    state = AsyncData(url);
    return url;
  }

  Future<void> disable() async {
    await ref.read(apiClientProvider).delete('/guardian/link');
    state = const AsyncData(null);
  }
}

final guardianProvider = AsyncNotifierProvider<GuardianController, String?>(GuardianController.new);

/// WhatsApp precisa do código do país: números brasileiros com DDD ganham o 55.
String whatsappNumber(String phone) {
  final digits = phone.replaceAll(RegExp(r'\D'), '');
  return digits.length <= 11 ? '55$digits' : digits;
}

/// Envia o link pelo WhatsApp (para o primeiro contato de emergência, se houver).
Future<void> sendGuardianLink(BuildContext context, WidgetRef ref, String url) async {
  final name = ref.read(sessionProvider).user?.firstName ?? '';
  final text = 'Oi! ${name.isEmpty ? 'Estou' : 'Aqui é $name, estou'} usando o ThermoGuia. Por este link você acompanha, '
      'em tempo real, se estou bebendo água como o app orienta e vê na hora se eu tocar em "Estou passando mal": $url';
  List<EmergencyContact> contacts = const [];
  try {
    contacts = await ref.read(safetyRepositoryProvider).contacts();
  } catch (_) {}
  final to = contacts.isEmpty ? '' : whatsappNumber(contacts.first.phone);
  final opened = await launchUrl(
    Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}'),
    mode: LaunchMode.externalApplication,
  );
  if (!opened && context.mounted) showMessage(context, 'Não foi possível abrir o WhatsApp.');
}

/// Cartão do Perfil: o diferencial do perfil idoso (disponível para todos).
class GuardianCard extends ConsumerWidget {
  const GuardianCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final idoso = ref.watch(personaProvider) == Persona.idoso;
    final link = ref.watch(guardianProvider);
    final url = link.valueOrNull;

    Future<void> run(Future<void> Function() action) async {
      try {
        await action();
      } catch (e) {
        if (context.mounted) showMessage(context, errorText(e));
      }
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Tokens.radiusBlock),
        color: idoso ? scheme.primaryContainer.withValues(alpha: 0.35) : null,
        border: Border.all(color: idoso ? scheme.primary.withValues(alpha: 0.4) : scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.family_restroom, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(child: Text('Acompanhamento do responsável', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
          if (url != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: Tokens.copa, borderRadius: BorderRadius.circular(20)),
              child: Text('Ativo', style: t.labelSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
            ),
        ]),
        const SizedBox(height: 8),
        Text(
          'Seu contato de emergência acompanha em tempo real se você está bebendo água como o app orienta '
          'e recebe um alerta quando você toca em "Estou passando mal".',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 8),
        if (link.isLoading)
          const LinearProgressIndicator()
        else if (url == null)
          FilledButton.icon(
            icon: const Icon(Icons.send_outlined),
            label: const Text('Ativar e enviar ao responsável'),
            onPressed: () => run(() async {
              final u = await ref.read(guardianProvider.notifier).enable();
              if (context.mounted) await sendGuardianLink(context, ref, u);
            }),
          )
        else
          Wrap(spacing: 4, children: [
            TextButton.icon(
              icon: const Icon(Icons.send_outlined),
              label: const Text('Reenviar link'),
              onPressed: () => run(() => sendGuardianLink(context, ref, url)),
            ),
            TextButton.icon(
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Ver o que ele vê'),
              onPressed: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            ),
            TextButton(
              style: TextButton.styleFrom(foregroundColor: scheme.error),
              onPressed: () => run(() async {
                await ref.read(guardianProvider.notifier).disable();
                if (context.mounted) showMessage(context, 'Acompanhamento desativado. O link antigo parou de funcionar.');
              }),
              child: const Text('Desativar'),
            ),
          ]),
        TextButton(
          style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
          onPressed: () => context.push('/contatos'),
          child: const Text('Contatos de emergência'),
        ),
      ]),
    );
  }
}
