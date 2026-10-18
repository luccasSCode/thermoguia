import 'package:flutter/material.dart';

import '../theme/tokens.dart';
import 'leaf_icon.dart';

/// A folha do ícone brota, o sol aparece, a nervura vira rota e o caule
/// marca o lugar. Mesmo roteiro e mesmas curvas do arquivo de animação.
///
/// Sem [loop], para no ícone pronto ([until] do ciclo de 5,5 s) e chama
/// [onDone]. Com "Reduzir movimento" ligado, mostra o ícone pronto na hora.
class LeafAnimation extends StatefulWidget {
  const LeafAnimation({
    super.key,
    this.size = 200,
    this.background = false,
    this.loop = false,
    this.until = 0.8,
    this.onDone,
  });

  final double size;
  final bool background;
  final bool loop;
  final double until;
  final VoidCallback? onDone;

  static const cycle = Duration(milliseconds: 5500);

  @override
  State<LeafAnimation> createState() => _LeafAnimationState();
}

class _LeafAnimationState extends State<LeafAnimation> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: LeafAnimation.cycle);
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.value = widget.until;
      WidgetsBinding.instance.addPostFrameCallback((_) => widget.onDone?.call());
    } else if (widget.loop) {
      _ctrl.repeat();
    } else {
      _ctrl.animateTo(widget.until).whenCompleteOrCancel(() {
        if (mounted) widget.onDone?.call();
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final onLight = Theme.of(context).brightness == Brightness.light;
    return Semantics(
      image: true,
      label: 'ThermoGuia Manaus',
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => CustomPaint(
            size: Size.square(widget.size),
            painter: LeafIconPainter(
              frame: LeafFrame.at(_ctrl.value),
              background: widget.background,
              onLight: onLight,
            ),
          ),
        ),
      ),
    );
  }
}

/// Abertura do app: a animação da folha sobre a cor da tela de abertura
/// nativa (que fica vazia), depois some suavemente. Um toque pula.
class AnimatedSplash extends StatefulWidget {
  const AnimatedSplash({super.key, required this.child});
  final Widget child;

  @override
  State<AnimatedSplash> createState() => _AnimatedSplashState();
}

class _AnimatedSplashState extends State<AnimatedSplash> {
  bool _fading = false;
  bool _gone = false;

  void _finish() {
    if (_fading || !mounted) return;
    setState(() => _fading = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_gone) return widget.child;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        widget.child,
        Positioned.fill(
          child: AnimatedOpacity(
            opacity: _fading ? 0 : 1,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOut,
            onEnd: () {
              if (_fading) setState(() => _gone = true);
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _finish,
              child: ColoredBox(
                // Mesmas cores da tela de abertura nativa (pubspec, flutter_native_splash).
                color: dark ? Tokens.noite : Tokens.papel,
                child: Center(
                  child: LeafAnimation(
                    size: 220,
                    onDone: () => Future.delayed(const Duration(milliseconds: 250), _finish),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
