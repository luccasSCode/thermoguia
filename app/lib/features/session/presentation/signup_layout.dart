import 'package:flutter/material.dart';

/// Ilustração de Manaus no topo e o conteúdo embaixo, tudo numa tela só: a
/// ilustração encolhe (até [minHeaderHeight]) para o conteúdo caber sem rolar.
/// Só rola se nem assim couber, como com o teclado aberto.
class SignupLayout extends StatelessWidget {
  const SignupLayout({super.key, required this.child, this.minHeaderHeight = 0});
  final Widget child;
  final double minHeaderHeight;

  @override
  Widget build(BuildContext context) => CustomScrollView(
        slivers: [
          SliverFillRemaining(
            hasScrollBody: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              // Em telas altas, a sobra fica entre a ilustração e o conteúdo.
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: minHeaderHeight,
                      // Nunca maior que a ilustração inteira na largura da tela.
                      maxHeight: MediaQuery.sizeOf(context).width * 780 / 1170,
                    ),
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        image: DecorationImage(
                          image: AssetImage('assets/illustrations/signup_header.png'),
                          fit: BoxFit.cover,
                        ),
                      ),
                      child: SizedBox.expand(),
                    ),
                  ),
                ),
                child,
              ],
            ),
          ),
        ],
      );
}
