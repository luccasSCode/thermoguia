import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Base das animações do mapa: repete sem parar, ou fica parada quando o
/// aparelho pede menos movimento (acessibilidade).
abstract class _LoopState<T extends StatefulWidget> extends State<T> with SingleTickerProviderStateMixin {
  Duration get period;
  late final AnimationController loop = AnimationController(vsync: this, duration: period, value: 0.3);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      loop.stop();
    } else if (!loop.isAnimating) {
      loop.repeat();
    }
  }

  @override
  void dispose() {
    loop.dispose();
    super.dispose();
  }
}

/// Nuvem de fumaça que se mexe devagar sobre a região, na cor do ar.
class SmokeCloud extends StatefulWidget {
  const SmokeCloud({super.key, required this.color});
  final Color color;

  @override
  State<SmokeCloud> createState() => _SmokeCloudState();
}

class _SmokeCloudState extends _LoopState<SmokeCloud> {
  @override
  Duration get period => const Duration(seconds: 7);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(painter: _SmokePainter(loop, widget.color)),
        ),
      );
}

class _SmokePainter extends CustomPainter {
  _SmokePainter(this.t, this.color) : super(repaint: t);
  final Animation<double> t;
  final Color color;

  // Cinza da fumaça puxado para a cor do ar.
  static const _smoke = Color(0xFF6B6461);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final tint = Color.lerp(_smoke, color, 0.35)!;
    // Seis bolhas que sobem e voltam, cada uma no seu tempo.
    for (var i = 0; i < 6; i++) {
      final phase = (t.value + i / 6) % 1;
      final angle = i * math.pi / 3 + t.value * 2 * math.pi * 0.15;
      final drift = Offset(math.cos(angle), math.sin(angle) * 0.6) * r * 0.42;
      final rise = Offset(0, -r * 0.35 * phase);
      final radius = r * (0.2 + 0.14 * math.sin(phase * math.pi));
      final alpha = 0.55 * math.sin(phase * math.pi);
      canvas.drawCircle(
        c + drift + rise + Offset(0, r * 0.15),
        radius,
        Paint()
          ..color = tint.withValues(alpha: alpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.22),
      );
    }
  }

  @override
  bool shouldRepaint(_SmokePainter old) => old.color != color;
}

/// Sol que pulsa e gira devagar, marcando um lugar com sol forte.
class SunGlow extends StatefulWidget {
  const SunGlow({super.key});

  @override
  State<SunGlow> createState() => _SunGlowState();
}

class _SunGlowState extends _LoopState<SunGlow> {
  @override
  Duration get period => const Duration(seconds: 4);

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: RepaintBoundary(child: CustomPaint(painter: _SunPainter(loop))),
      );
}

class _SunPainter extends CustomPainter {
  _SunPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final pulse = 0.5 + 0.5 * math.sin(t.value * 2 * math.pi);

    // Brilho em volta.
    canvas.drawCircle(
      c,
      r * (0.75 + 0.15 * pulse),
      Paint()
        ..shader = RadialGradient(colors: [
          Tokens.sol.withValues(alpha: 0.45),
          Tokens.sol.withValues(alpha: 0),
        ]).createShader(Rect.fromCircle(center: c, radius: r)),
    );

    // Raios girando.
    final rays = Paint()
      ..color = const Color(0xFFFFB627)
      ..strokeWidth = r * 0.07
      ..strokeCap = StrokeCap.round;
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(t.value * math.pi / 4);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final dir = Offset(math.cos(a), math.sin(a));
      final len = i.isEven ? 0.2 + 0.06 * pulse : 0.14 + 0.06 * (1 - pulse);
      canvas.drawLine(dir * r * 0.36, dir * r * (0.36 + len), rays);
    }
    canvas.restore();

    // Disco do sol.
    canvas.drawCircle(c, r * 0.26, Paint()..color = const Color(0xFFFFB627));
    canvas.drawCircle(
      c,
      r * 0.26,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = r * 0.04
        ..color = Tokens.sol,
    );
  }

  @override
  bool shouldRepaint(_SunPainter old) => false;
}
