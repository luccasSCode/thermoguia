import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/common.dart';
import '../../../core/widgets/leaf_animation.dart';
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
        body: LayoutBuilder(
          // Rola só em telas baixas.
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Ilustração de Manaus no topo, por trás da barra de status.
                    const AspectRatio(
                      aspectRatio: 1170 / 780,
                      child: Image(
                        image: AssetImage('assets/illustrations/signup_header.png'),
                        fit: BoxFit.cover,
                        excludeFromSemantics: true,
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + insets.bottom),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Semantics(
                              header: true,
                              label: 'Thermo Guia',
                              child: ExcludeSemantics(
                                child: Row(children: [
                                  LeafAnimation(size: (t.displaySmall?.fontSize ?? 36) * 2),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text('Thermo Guia', style: t.displaySmall)),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Atravesse Manaus pela sombra.', style: t.titleMedium?.copyWith(fontSize: 24)),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                'O ThermoGuia acompanha o calor onde você está, sugere caminhos mais '
                                'frescos e avisa a hora de beber água.',
                                textAlign: TextAlign.center,
                                style: t.bodyLarge,
                              ),
                            ),
                            const SizedBox(height: 32),
                            // Divide o espaço que sobra: 1 parte acima dos botões, 2 abaixo.
                            const Spacer(),
                            FilledButton(
                              onPressed: () => context.go('/comecar'),
                              child: const Center(child: Text('Começar')),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: () => context.go('/entrar'),
                              child: const Center(child: Text('Já tenho conta')),
                            ),
                            const SizedBox(height: 20),
                            Row(children: [
                              const Expanded(child: Divider()),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('ou', style: t.bodyMedium),
                              ),
                              const Expanded(child: Divider()),
                            ]),
                            const SizedBox(height: 20),
                            // Os SDKs de login social ainda não estão configurados: o toque explica isso.
                            SocialSignInButtons(
                              onPressed: (p) => showMessage(
                                context,
                                'O login com ${p.brand} chega em breve. Por enquanto, toque em '
                                '"Começar" ou entre com seu e-mail.',
                              ),
                            ),
                            const Spacer(flex: 2),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
