import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'thermo_logo.dart';

/// Indicador de carregamento com a marca: a logo "respira" enquanto um arco
/// do azul do rio ao laranja do sol gira em volta dela.
///
/// Abaixo de [_logoMinSize] (dentro de botões, campos) só o arco aparece,
/// porque a logo ficaria pequena demais para ser reconhecida.
class ThermoLoader extends StatefulWidget {
  const ThermoLoader({super.key, this.size = 96, this.message});

  /// Versão compacta, para botões e linhas de texto.
  const ThermoLoader.inline({super.key, this.size = 22}) : message = null;

  final double size;
  final String? message;

  @override
  State<ThermoLoader> createState() => _ThermoLoaderState();
}

const _logoMinSize = 48.0;

class _ThermoLoaderState extends State<ThermoLoader> with SingleTickerProviderStateMixin {
  late final _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respeita "Reduzir movimento" do sistema.
    if (MediaQuery.disableAnimationsOf(context)) {
      _ctrl.stop();
      _ctrl.value = 0.25;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final withLogo = widget.size >= _logoMinSize;
    final stroke = withLogo ? (widget.size * 0.035).clamp(2.5, 5.0) : (widget.size * 0.12).clamp(2.0, 3.0);

    final loader = SizedBox.square(
      dimension: widget.size,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          final arc = CustomPaint(
            size: Size.square(widget.size),
            painter: _ArcPainter(
              turn: _ctrl.value,
              stroke: stroke.toDouble(),
              from: scheme.primary,
              to: scheme.secondary,
              track: scheme.onSurface.withValues(alpha: 0.08),
            ),
          );
          if (!withLogo) return arc;
          // Duas "respirações" por volta do arco.
          final breath = 0.5 - 0.5 * math.cos(_ctrl.value * 4 * math.pi);
          return Stack(
            alignment: Alignment.center,
            children: [
              arc,
              Transform.scale(
                scale: 0.94 + 0.06 * breath,
                child: ThermoLogo(size: widget.size * 0.66),
              ),
            ],
          );
        },
      ),
    );

    return Semantics(
      label: widget.message ?? 'Carregando',
      liveRegion: true,
      child: ExcludeSemantics(
        child: widget.message == null
            ? loader
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  loader,
                  const SizedBox(height: 16),
                  Text(widget.message!, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
                ],
              ),
      ),
    );
  }
}

class _ArcPainter extends CustomPainter {
  _ArcPainter({required this.turn, required this.stroke, required this.from, required this.to, required this.track});

  final double turn;
  final double stroke;
  final Color from;
  final Color to;
  final Color track;

  static const _sweep = math.pi * 1.1;
  // Folga para a ponta arredondada da cauda não cruzar o ângulo 0, onde o
  // gradiente "dá a volta" e pintaria um ponto laranja.
  static const _gap = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final arcRect = rect.deflate(stroke / 2);
    canvas.drawArc(arcRect, 0, math.pi * 2, false, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = track);

    // Gira a tela em vez do gradiente: o arco sempre vai de _gap a _sweep,
    // com a cauda transparente e a ponta laranja.
    final center = rect.center;
    canvas
      ..save()
      ..translate(center.dx, center.dy)
      ..rotate(turn * math.pi * 2 - math.pi / 2)
      ..translate(-center.dx, -center.dy);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        endAngle: _sweep,
        colors: [from.withValues(alpha: 0), from, to],
        stops: const [0, 0.4, 1],
      ).createShader(rect);
    canvas
      ..drawArc(arcRect, _gap, _sweep - _gap, false, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_ArcPainter old) =>
      old.turn != turn || old.from != from || old.to != to || old.track != track || old.stroke != stroke;
}
