import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import 'safety_repository.dart';
import '../../core/widgets/thermo_loader.dart';

class ContactsScreen extends ConsumerWidget {
  const ContactsScreen({super.key});

  Future<void> _add(BuildContext context, WidgetRef ref) async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final relation = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Novo contato'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Nome')),
          const SizedBox(height: 12),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Telefone com DDD', hintText: '+55 92 99999-9999'),
          ),
          const SizedBox(height: 12),
          TextField(controller: relation, decoration: const InputDecoration(labelText: 'Relação (ex.: filha)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar contato')),
        ],
      ),
    );
    if (ok != true) return;
    var p = phone.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (!p.startsWith('+')) p = p.startsWith('55') ? '+$p' : '+55$p';
    try {
      await ref.read(safetyRepositoryProvider).addContact(name.text.trim(), p, relation.text.trim());
      ref.invalidate(contactsProvider);
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contacts = ref.watch(contactsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Contatos de emergência')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context, ref),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Adicionar contato'),
      ),
      body: contacts.when(
        loading: () => const Center(child: ThermoLoader()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(contactsProvider)),
        data: (list) => ListView(
          padding: const EdgeInsets.only(bottom: 96),
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Essas pessoas podem receber sua localização se você passar mal. '
                'Nada é enviado sem a sua confirmação.',
              ),
            ),
            if (list.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: Text('Nenhum contato ainda. Adicione alguém de confiança.'),
              ),
            for (final c in list)
              ListTile(
                leading: const Icon(Icons.person_outline),
                title: Text(c.name),
                subtitle: Text([c.relation, c.phone].where((s) => s.isNotEmpty).join(', ')),
                trailing: IconButton(
                  tooltip: 'Remover ${c.name}',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    await ref.read(safetyRepositoryProvider).removeContact(c.id);
                    ref.invalidate(contactsProvider);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
