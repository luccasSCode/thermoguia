import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/leaf_icon.dart';

const _channel = MethodChannel('thermoguia/app_icon');

String _label(LeafVariant v) => switch (v) {
      LeafVariant.padrao => 'Padrão',
      LeafVariant.escuro => 'Escuro',
      LeafVariant.tingido => 'Tingido',
    };

/// No Android, o ícone é escolhido no app (activity-alias, ver MainActivity.kt).
/// No iPhone, o próprio sistema troca entre as variantes.
bool get canChooseAppIcon => !kIsWeb && Platform.isAndroid;

class AppIconController extends AsyncNotifier<LeafVariant> {
  @override
  Future<LeafVariant> build() async {
    if (!canChooseAppIcon) return LeafVariant.padrao;
    final name = await _channel.invokeMethod<String>('get');
    return LeafVariant.values.firstWhere((v) => v.name == name, orElse: () => LeafVariant.padrao);
  }

  Future<void> select(LeafVariant v) async {
    await _channel.invokeMethod<void>('set', {'name': v.name});
    state = AsyncData(v);
  }
}

final appIconProvider = AsyncNotifierProvider<AppIconController, LeafVariant>(AppIconController.new);

/// Seção "Ícone do app" do Perfil: as três variantes lado a lado.
class AppIconPicker extends ConsumerWidget {
  const AppIconPicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context).textTheme;
    final selected = ref.watch(appIconProvider).valueOrNull;
    final choose = canChooseAppIcon;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final v in LeafVariant.values)
              _IconOption(
                variant: v,
                selected: choose && v == selected,
                onTap: choose && v != selected
                    ? () async {
                        try {
                          await ref.read(appIconProvider.notifier).select(v);
                          if (context.mounted) {
                            showMessage(context, 'Ícone ${_label(v)} escolhido. A tela inicial pode levar alguns segundos para mudar.');
                          }
                        } on PlatformException {
                          if (context.mounted) showMessage(context, 'Não foi possível trocar o ícone neste aparelho.');
                        }
                      }
                    : null,
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          choose
              ? 'Com "Ícones temáticos" ligado (Android 13 ou mais recente), o ícone acompanha as cores do seu papel de parede.'
              : 'No iPhone, o ícone segue o sistema: toque e segure a Tela de Início, escolha Editar → Personalizar '
                  'e selecione Escuro ou Tingido (iOS 18 ou mais recente).',
          style: t.bodyMedium,
        ),
      ]),
    );
  }
}

class _IconOption extends StatelessWidget {
  const _IconOption({required this.variant, required this.selected, required this.onTap});
  final LeafVariant variant;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: 'Ícone ${_label(variant)}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusControl),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(children: [
            Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: selected ? scheme.primary : Colors.transparent, width: 3),
              ),
              child: CustomPaint(size: const Size.square(64), painter: LeafIconPainter(variant: variant)),
            ),
            const SizedBox(height: 6),
            ExcludeSemantics(
              child: Text(
                _label(variant),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : null,
                      color: selected ? scheme.primary : null,
                    ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
