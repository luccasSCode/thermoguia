import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/widgets/common.dart';
import '../climate/climate_providers.dart';
import 'safety_repository.dart';
import '../../core/widgets/thermo_loader.dart';

/// Fluxo "Estou passando mal".
///
/// Princípio: o agente orienta, mas qualquer ação que envolva terceiros
/// (ligar para o SAMU, enviar localização) só acontece após confirmação
/// explícita — e a decisão, aceita ou recusada, vai para o histórico.
Future<void> showEmergencySheet(BuildContext context, {required String trigger}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EmergencySheet(trigger: trigger),
    );

const _symptoms = {
  'tontura': 'Tontura ou fraqueza',
  'dor_cabeca': 'Dor de cabeça forte',
  'nausea': 'Enjoo ou vômito',
  'caibras': 'Cãibras',
  'pele_quente': 'Pele muito quente e seca',
  'confusao': 'Confusão ou fala enrolada',
  'desmaio': 'Desmaio (meu ou de alguém perto)',
};
const _severe = {'confusao', 'desmaio', 'pele_quente'};

class _EmergencySheet extends ConsumerStatefulWidget {
  const _EmergencySheet({required this.trigger});
  final String trigger;

  @override
  ConsumerState<_EmergencySheet> createState() => _EmergencySheetState();
}

class _EmergencySheetState extends ConsumerState<_EmergencySheet> {
  final _selected = <String>{};
  bool _busy = false;

  bool get _isSevere => _selected.any(_severe.contains);

  @override
  void initState() {
    super.initState();
    ref.read(auditLoggerProvider).log('emergencia_aberta', details: {'gatilho': widget.trigger});
    if (widget.trigger == 'usuario') ref.read(safetyRepositoryProvider).helpAlert();
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ??
      false;

  Future<void> _callSamu() async {
    final ok = await _confirm(
      'Ligar para o SAMU (192)?',
      'O telefone vai abrir com o número 192 pronto para chamar.',
      'Ligar',
    );
    await ref.read(safetyRepositoryProvider).logEvent(
          action: 'call_samu',
          approved: ok,
          symptoms: _selected.toList(),
          trigger: widget.trigger,
          riskLevel: ref.read(riskProvider)?.level.name,
        );
    if (ok) await launchUrl(Uri.parse('tel:192'));
  }

  Future<void> _notifyContacts() async {
    final repo = ref.read(safetyRepositoryProvider);
    setState(() => _busy = true);
    try {
      final contacts = await repo.contacts();
      if (!mounted) return;
      if (contacts.isEmpty) {
        showMessage(context, 'Cadastre um contato de emergência no Perfil primeiro.');
        return;
      }
      final names = contacts.map((c) => c.name).join(', ');
      final ok = await _confirm(
        'Enviar sua localização?',
        'Sua localização atual e um pedido de ajuda serão preparados para: $names. '
            'Você confirma o envio no WhatsApp ou SMS.',
        'Confirmar',
      );
      final loc = (await ref.read(userLocationProvider.future)).point;
      final result = await repo.logEvent(
        action: 'share_location',
        approved: ok,
        symptoms: _selected.toList(),
        trigger: widget.trigger,
        riskLevel: ref.read(riskProvider)?.level.name,
        contactIds: contacts.map((c) => c.id).toList(),
        lat: ok ? loc.lat : null,
        lng: ok ? loc.lng : null,
      );
      final message = result['message'] as String?;
      if (!ok || message == null) return;
      final first = contacts.first;
      final phone = first.phone.replaceAll('+', '');
      final wa = Uri.parse('https://wa.me/$phone?text=${Uri.encodeComponent(message)}');
      final opened = await launchUrl(wa, mode: LaunchMode.externalApplication);
      if (!opened) await launchUrl(Uri.parse('sms:${first.phone}?body=${Uri.encodeComponent(message)}'));
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final error = Theme.of(context).colorScheme.error;
    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      children: [
        Text('Faça isso agora', style: t.headlineSmall),
        const SizedBox(height: 12),
        for (final step in const [
          'Pare e vá para a sombra ou um lugar com ar-condicionado.',
          'Beba água em pequenos goles.',
          'Afrouxe as roupas e molhe nuca, pulsos e rosto.',
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.check_circle_outline, size: 22),
              const SizedBox(width: 10),
              Expanded(child: Text(step, style: t.bodyLarge)),
            ]),
          ),
        const SizedBox(height: 16),
        Text('O que você está sentindo?', style: t.titleMedium),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final e in _symptoms.entries)
            FilterChip(
              label: Text(e.value),
              selected: _selected.contains(e.key),
              onSelected: (v) => setState(() => v ? _selected.add(e.key) : _selected.remove(e.key)),
            ),
        ]),
        if (_isSevere) ...[
          const SizedBox(height: 16),
          Text(
            'Esses sinais podem indicar insolação. Ligue para o SAMU agora.',
            style: t.titleMedium?.copyWith(color: error),
          ),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: error),
          icon: const Icon(Icons.call),
          label: const Text('Ligar para o SAMU (192)'),
          onPressed: _callSamu,
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: _busy
              ? const ThermoLoader.inline(size: 18)
              : const Icon(Icons.share_location),
          label: const Text('Avisar meus contatos'),
          onPressed: _busy ? null : _notifyContacts,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () async {
            await ref.read(safetyRepositoryProvider).logEvent(
                  action: 'dismiss',
                  approved: false,
                  symptoms: _selected.toList(),
                  trigger: widget.trigger,
                );
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Estou melhor'),
        ),
      ],
    );
  }
}
