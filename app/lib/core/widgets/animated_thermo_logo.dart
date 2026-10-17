import 'dart:math' as math;
import 'dart:ui' show PathMetric, lerpDouble;

import 'package:flutter/material.dart';

/// Logo animada da tela de boas-vindas, desenhada em vetor a partir de
/// `assets/branding/logo.png` (coordenadas no quadro de 1024×1024).
///
/// Roteiro: a folha brota do caule e balança; depois o sol sobe, a nervura se
/// desenha como rota (do caule até o pino) e o ponto final pulsa sem parar.
/// Com "Reduzir movimento" ligado, mostra a logo pronta, sem animação.
class AnimatedThermoLogo extends StatefulWidget {
  const AnimatedThermoLogo({super.key, this.size = 200}) : leafOnly = false;

  /// Só a folha inclinada (com caule, rota e pino) e o sol, sem o quadro verde.
  /// [size] é a altura; a largura segue a proporção do desenho.
  const AnimatedThermoLogo.mark({super.key, this.size = 48}) : leafOnly = true;

  final double size;
  final bool leafOnly;

  @override
  State<AnimatedThermoLogo> createState() => _AnimatedThermoLogoState();
}

class _AnimatedThermoLogoState extends State<AnimatedThermoLogo> with TickerProviderStateMixin {
  late final _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 3000));
  late final _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));
  bool _started = false;

  @override
  void initState() {
    super.initState();
    _intro.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) _pulse.repeat();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        image: true,
        label: 'ThermoGuia Manaus',
        child: RepaintBoundary(
          child: CustomPaint(
            size: widget.leafOnly
                ? Size(widget.size * _LogoPainter.leafBox.width / _LogoPainter.leafBox.height, widget.size)
                : Size.square(widget.size),
            painter: _LogoPainter(intro: _intro, pulse: _pulse, leafOnly: widget.leafOnly),
          ),
        ),
      );
}

/// Trecho [begin, end] da linha do tempo (0–1), já com a curva aplicada.
double _phase(double t, double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
    curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

class _LogoPainter extends CustomPainter {
  _LogoPainter({required this.intro, required this.pulse, required this.leafOnly})
      : super(repaint: Listenable.merge([intro, pulse]));

  /// Área da folha e do sol no quadro 1024, com folga para o caule e o pulso do pino.
  static const leafBox = Rect.fromLTRB(185, 215, 815, 870);

  final Animation<double> intro;
  final Animation<double> pulse;
  final bool leafOnly;

  // Cores tiradas da logo.
  static const _bgColors = [Color(0xFF76CEAD), Color(0xFF2EA586), Color(0xFF27695F), Color(0xFF004A50)];
  static const _warm = Color(0xFFEAD089);
  static const _ink = Color(0xFF145C53);
  static const _sunLight = Color(0xFFFFD98A);
  static const _sunDeep = Color(0xFFFF8C3A);

  // Pontos-chave da folha (quadro 1024).
  static const _base = Offset(512, 762);
  static const _pin = Offset(318, 330);
  static const _stemEnd = Offset(600, 835);
  static const _sun = Offset(711, 320);

  static final _leftHalf = Path()
    ..moveTo(300, 275)
    ..cubicTo(195, 390, 250, 670, 505, 765)
    ..cubicTo(470, 560, 340, 430, 300, 275)
    ..close();

  static final _rightHalf = Path()
    ..moveTo(308, 272)
    ..cubicTo(480, 320, 640, 600, 518, 755)
    ..cubicTo(470, 560, 340, 430, 308, 272)
    ..close();

  /// Nervura = rota: sai do caule e sobe até o pino.
  static final _vein = Path()
    ..moveTo(505, 745)
    ..cubicTo(465, 575, 345, 445, 322, 362);

  static final _stem = Path()
    ..moveTo(_base.dx, _base.dy)
    ..cubicTo(520, 805, 545, 832, _stemEnd.dx - 20, _stemEnd.dy);

  @override
  void paint(Canvas canvas, Size size) {
    final t = intro.value;
    canvas.save();
    if (leafOnly) {
      canvas
        ..scale(size.height / leafBox.height)
        ..translate(-leafBox.left, -leafBox.top);
    } else {
      canvas.scale(size.width / 1024);
    }

    // Linha do tempo (fração dos 3 s).
    final bg = _phase(t, 0.00, 0.12);
    final stem = _phase(t, 0.05, 0.22);
    final sprout = _phase(t, 0.15, 0.42, Curves.easeOutBack);
    final swayT = _phase(t, 0.30, 0.62, Curves.linear);
    final sunUp = _phase(t, 0.48, 0.70);
    final route = _phase(t, 0.66, 0.90, Curves.easeInOut);
    final pinIn = _phase(t, 0.88, 1.00, Curves.easeOutBack);

    // Fundo arredondado: tudo que sobe ou brota fica recortado nele.
    final frame = RRect.fromRectAndRadius(const Rect.fromLTWH(0, 0, 1024, 1024), const Radius.circular(225));
    canvas
      ..save()
      ..clipRRect(frame);
    if (!leafOnly) _paintBackdrop(canvas, frame, bg);
    _paintSun(canvas, sunUp);
    // Caule: cresce do ponto de origem até a base da folha.
    if (stem > 0) {
      final white = Paint()..color = Colors.white;
      canvas.drawCircle(_stemEnd, 26 * stem, white);
      final m = _stem.computeMetrics().first;
      // Desenha do ponto para a folha: extrai o trecho final do caminho.
      canvas.drawPath(
        m.extractPath(m.length * (1 - stem), m.length),
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = 22
          ..strokeCap = StrokeCap.round,
      );
    }

    // Folha: brota da base e balança com amortecimento.
    if (sprout > 0) {
      final sway = swayT == 0 || swayT == 1 ? 0.0 : 0.12 * math.sin(swayT * math.pi * 4) * (1 - swayT);
      canvas
        ..save()
        ..translate(_base.dx, _base.dy)
        ..rotate(sway)
        ..scale(sprout)
        ..translate(-_base.dx, -_base.dy);

      canvas
        ..drawPath(
          _leftHalf,
          Paint()
            ..shader = const LinearGradient(colors: [Color(0xFFF2FBF7), Color(0xFFDDF3EA)])
                .createShader(const Rect.fromLTWH(195, 272, 320, 495)),
        )
        ..drawPath(
          _rightHalf,
          Paint()
            ..shader = const LinearGradient(colors: [Color(0xFFCDEFE2), Color(0xFF8EDCC0)])
                .createShader(const Rect.fromLTWH(300, 272, 340, 495)),
        );
      // Sem o quadro verde, um contorno no verde da logo separa a folha do fundo claro.
      if (leafOnly) {
        final edge = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10
          ..strokeJoin = StrokeJoin.round
          ..color = _bgColors[1];
        canvas
          ..drawPath(_leftHalf, edge)
          ..drawPath(_rightHalf, edge);
      }

      // Rota: pontos que aparecem um a um, do caule até o pino.
      if (route > 0) _drawDots(canvas, _vein.computeMetrics().first, route);

      // Pino (ponto final da rota) e o pulso em volta dele.
      if (pinIn > 0) {
        if (t >= 1) {
          final p = pulse.value;
          canvas.drawCircle(
            _pin,
            30 + 60 * Curves.easeOut.transform(p),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 10 * (1 - p) + 2
              ..color = _ink.withValues(alpha: 0.55 * (1 - p)),
          );
        }
        final beat = t >= 1 ? 1 + 0.08 * math.sin(pulse.value * math.pi * 2) : pinIn;
        canvas
          ..drawCircle(
            _pin,
            30 * beat,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 12
              ..color = _ink,
          )
          ..drawCircle(_pin, 9 * beat, Paint()..color = _ink);
      }
      canvas.restore();
    }

    canvas
      ..restore()
      ..restore();
  }

  /// Quadro verde e brilho quente (só na logo completa).
  void _paintBackdrop(Canvas canvas, RRect frame, double bg) {
    final bgPaint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: _bgColors,
        stops: [0, 0.4, 0.7, 1],
      ).createShader(const Rect.fromLTWH(0, 0, 1024, 1024));
    canvas.drawRRect(frame, bgPaint..color = Colors.white.withValues(alpha: bg));
    // Brilho quente no canto de cima, como na logo.
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 1024, 1024),
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topRight,
          radius: 0.75,
          colors: [_warm.withValues(alpha: 0.9 * bg), _warm.withValues(alpha: 0)],
        ).createShader(const Rect.fromLTWH(0, 0, 1024, 1024)),
    );
  }

  /// Sol: sobe de baixo da folha até o lugar dele.
  void _paintSun(Canvas canvas, double sunUp) {
    if (sunUp > 0) {
      final c = Offset(_sun.dx, lerpDouble(_sun.dy + 280, _sun.dy, sunUp)!);
      final r = 95.0;
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [_sunLight.withValues(alpha: sunUp), _sunDeep.withValues(alpha: sunUp)],
          ).createShader(Rect.fromCircle(center: c, radius: r)),
      );
    }
  }

  void _drawDots(Canvas canvas, PathMetric m, double progress) {
    const gap = 23.0;
    final paint = Paint()..color = _ink;
    final end = m.length * progress;
    // Linha da rota por baixo dos pontos, como na logo.
    canvas.drawPath(
      m.extractPath(0, end),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = _ink.withValues(alpha: 0.45),
    );
    for (var d = 0.0; d <= end; d += gap) {
      final pos = m.getTangentForOffset(d)!.position;
      canvas.drawCircle(pos, 8, paint);
    }
  }

  @override
  bool shouldRepaint(_LogoPainter old) => false;
}
