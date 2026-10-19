import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/leaf_animation.dart';
import 'signup_layout.dart';
import 'social_sign_in.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final insets = MediaQuery.paddingOf(context);
    // O céu da ilustração é claro: ícones escuros na barra de status.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SignupLayout(
          // A ilustração fica por trás da barra de status e nunca some de todo.
          minHeaderHeight: insets.top + 48,
          child: Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 16 + insets.bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  header: true,
                  label: 'Thermo Guia',
                  child: ExcludeSemantics(
                    child: Row(children: [
                      LeafAnimation(size: (t.displaySmall?.fontSize ?? 36) * 1.5),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text('Thermo Guia', maxLines: 1, style: t.displaySmall),
                        ),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Atravesse Manaus pela sombra e longe da fumaça.',
                  textAlign: TextAlign.center,
                  style: t.titleMedium?.copyWith(fontSize: 22),
                ),
                const SizedBox(height: 8),
                Text(
                  'O ThermoGuia acompanha o calor e a fumaça onde você está, sugere caminhos '
                  'mais frescos, avisa quando usar máscara e a hora de beber água.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium,
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => context.go('/comecar'),
                  child: const Text('Começar'),
                ),
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: () => context.go('/entrar'),
                  child: const Text('Já tenho conta'),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  const Expanded(child: Divider()),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('ou', style: t.bodyMedium),
                  ),
                  const Expanded(child: Divider()),
                ]),
                const SizedBox(height: 12),
                // Só ilustrativos por enquanto: levam ao cadastro, como o Começar.
                SocialSignInButtons(onPressed: () => context.go('/comecar')),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
