import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/common.dart';
import 'safety_repository.dart';
import '../../core/widgets/thermo_loader.dart';

final _historyProvider = FutureProvider.autoDispose((ref) => ref.watch(safetyRepositoryProvider).history());

const _labels = {
  'consentimento_inicial': 'Permissões aceitas no cadastro',
  'conta_criada': 'Conta criada',
  'conta_excluida': 'Conta excluída',
  'emergencia_aberta': 'Abriu "Estou passando mal"',
  'emergencia_call_samu': 'Ligação para o SAMU',
  'emergencia_share_location': 'Envio de localização a contatos',
  'emergencia_dismiss': 'Encerrou o alerta ("Estou melhor")',
  'contato_emergencia_adicionado': 'Contato de emergência adicionado',
  'contato_emergencia_removido': 'Contato de emergência removido',
  'alerta_calor_extremo': 'Alerta de calor extremo enviado',
  'trajeto_iniciado': 'Trajeto iniciado',
  'relato_comunidade': 'Relato publicado no mapa',
  'aprendizado_reiniciado': 'Aprendizado reiniciado',
  'interesse_plano': 'Interesse em plano pago',
};

/// Histórico de decisões: tudo o que o agente sugeriu e o que você aprovou.
class AuditScreen extends ConsumerWidget {
  const AuditScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final h = ref.watch(_historyProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Histórico de decisões')),
      body: h.when(
        loading: () => const Center(child: ThermoLoader()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_historyProvider)),
        data: (list) => list.isEmpty
            ? const Center(child: Text('Nenhuma decisão registrada ainda.'))
            : ListView.separated(
                itemCount: list.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final e = list[i];
                  final d = e.at;
                  return ListTile(
                    leading: Icon(switch (e.approved) {
                      true => Icons.check_circle_outline,
                      false => Icons.block,
                      null => Icons.info_outline,
                    }),
                    title: Text(_labels[e.action] ?? e.action),
                    subtitle: Text(
                      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')} às ${hm(d)}'
                      '${e.approved == null ? '' : e.approved! ? ', aprovado por você' : ', recusado por você'}',
                    ),
                  );
                },
              ),
      ),
    );
  }
}
