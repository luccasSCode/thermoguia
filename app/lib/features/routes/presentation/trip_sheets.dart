import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/providers.dart';
import '../../../core/widgets/common.dart';
import '../data/route_models.dart';
import '../../rewards/rewards_controller.dart';
import 'routes_controller.dart';

/// Pergunta pós-trajeto: é daqui que o agente aprende a sensibilidade.
Future<ComfortFeedback?> showComfortFeedback(BuildContext context) =>
    showModalBottomSheet<ComfortFeedback>(
      context: context,
      isDismissible: false,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Como você se sentiu no trajeto?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Sua resposta ajusta as próximas recomendações ao seu corpo.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 20),
              for (final f in ComfortFeedback.values) ...[
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(ctx, f),
                  icon: Icon(switch (f) {
                    ComfortFeedback.confortavel => Icons.sentiment_satisfied_alt,
                    ComfortFeedback.calor => Icons.sentiment_neutral,
                    ComfortFeedback.muitoCalor => Icons.sick_outlined,
                  }),
                  label: Text(f.label),
                ),
                const SizedBox(height: 8),
              ],
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Pular')),
            ],
          ),
        ),
      ),
    );

Future<void> showReportSheet(BuildContext context, WidgetRef ref, GeoPoint at) async {
  final note = TextEditingController();
  final kind = await showModalBottomSheet<ReportKind>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('O que tem neste ponto?', style: Theme.of(ctx).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Seu relato melhora as Rotas Frescas de todo mundo.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: note,
                maxLength: 140,
                decoration: const InputDecoration(labelText: 'Detalhe (opcional)'),
              ),
              for (final k in ReportKind.values)
                ListTile(
                  leading: Icon(reportIcon(k)),
                  title: Text(k.label),
                  onTap: () => Navigator.pop(ctx, k),
                ),
            ],
          ),
        ),
      ),
    ),
  );
  if (kind == null) return;
  try {
    final res = await ref.read(routesRepositoryProvider).addReport(kind, at, note.text.trim());
    ref.read(rewardsProvider.notifier).announceFrom(res);
    await ref.read(auditLoggerProvider).log('relato_comunidade', details: {'tipo': kind.api});
    ref.invalidate(reportsProvider);
    if (context.mounted) showMessage(context, 'Obrigado! Relato publicado.');
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
  }
}

IconData reportIcon(ReportKind k) => switch (k) {
      ReportKind.sombraBoa => Icons.park,
      ReportKind.semSombra => Icons.wb_sunny,
      ReportKind.bebedouro => Icons.water_drop,
      ReportKind.calorExtremo => Icons.local_fire_department,
      ReportKind.alagamento => Icons.flood,
      ReportKind.transito => Icons.traffic,
      ReportKind.obra => Icons.construction,
    };

IconData oasisIcon(String kind) => switch (kind) {
      'bebedouro' => Icons.water_drop,
      'shopping' => Icons.ac_unit,
      'farmacia' => Icons.local_pharmacy,
      'supermercado' => Icons.shopping_cart,
      'biblioteca' => Icons.local_library,
      _ => Icons.park,
    };
