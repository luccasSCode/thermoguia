import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

/// Ícone "Folha inclinada" desenhado em vetor, no quadro de 100×100 do
/// arquivo de design. A mesma pintura gera os PNGs do ícone do app
/// (tool/render_brand_assets.dart) e anima a abertura ([LeafFrame.at]).
enum LeafVariant { padrao, escuro, tingido }

class LeafPalette {
  const LeafPalette({
    required this.bg,
    required this.bgStops,
    required this.glow,
    required this.glowAlpha,
    required this.glow2,
    required this.glow2Alpha,
    required this.highlightAlpha,
    required this.leafLeft,
    required this.leafRight,
    required this.sun,
    required this.ink,
    required this.stem,
  });

  final List<Color> bg;
  final List<double> bgStops;
  final Color glow;
  final List<double> glowAlpha;
  final Color glow2;
  final double glow2Alpha;
  final double highlightAlpha;
  final List<Color> leafLeft;
  final List<Color> leafRight;
  final List<Color> sun;
  final Color ink;
  final Color stem;

  static LeafPalette of(LeafVariant v) => switch (v) {
        LeafVariant.padrao => padrao,
        LeafVariant.escuro => escuro,
        LeafVariant.tingido => tingido,
      };

  static const padrao = LeafPalette(
    bg: [Color(0xFF58C995), Color(0xFF178A6E), Color(0xFF073A3F)],
    bgStops: [0, 0.5, 1],
    glow: Color(0xFFFFC25A),
    glowAlpha: [0.95, 0.33, 0],
    glow2: Color(0xFFB8FF9E),
    glow2Alpha: 0.35,
    highlightAlpha: 0.22,
    leafLeft: [Color(0xFFFFFFFF), Color(0xFFC8F3E2)],
    leafRight: [Color(0xFFE3FAF1), Color(0xFF86DDBB)],
    sun: [Color(0xFFFFE08A), Color(0xFFFF8A3D)],
    ink: Color(0xFF0E5E57),
    stem: Color(0xFFFFFFFF),
  );

  static const escuro = LeafPalette(
    bg: [Color(0xFF16302B), Color(0xFF050D0C)],
    bgStops: [0, 1],
    glow: Color(0xFFFFB84A),
    glowAlpha: [0.25, 0.09, 0],
    glow2: Color(0xFF1FB89A),
    glow2Alpha: 0.15,
    highlightAlpha: 0.08,
    leafLeft: [Color(0xFFF2FFF9), Color(0xFF9FE8CC)],
    leafRight: [Color(0xFFC8F3E2), Color(0xFF4FC69D)],
    sun: [Color(0xFFFFD06A), Color(0xFFFF7A2E)],
    ink: Color(0xFF0A3A35),
    stem: Color(0xFFE8F7F1),
  );

  static const tingido = LeafPalette(
    bg: [Color(0xFF2A2A2A), Color(0xFF121212)],
    bgStops: [0, 1],
    glow: Color(0xFFFFFFFF),
    glowAlpha: [0.05, 0.02, 0],
    glow2: Color(0xFF000000),
    glow2Alpha: 0,
    highlightAlpha: 0.08,
    leafLeft: [Color(0xFFFFFFFF), Color(0xFFE4E4E4)],
    leafRight: [Color(0xFFBDBDBD), Color(0xFF9A9A9A)],
    sun: [Color(0xFF7A7A7A), Color(0xFF5E5E5E)],
    ink: Color(0xFF1C1C1C),
    stem: Color(0xFFE4E4E4),
  );
}

/// Um quadro da animação. [rest] é o ícone pronto, parado.
class LeafFrame {
  const LeafFrame({
    this.leafTurnDeg = 0,
    this.leafScale = 1,
    this.leafOpacity = 1,
    this.sunOffset = Offset.zero,
    this.sunOpacity = 1,
    this.originScale = 1,
    this.reveal = 1,
    this.stemOpacity = 1,
    this.destScale = 1,
    this.glow = 1,
  });

  final double leafTurnDeg;
  final double leafScale;
  final double leafOpacity;
  final Offset sunOffset;
  final double sunOpacity;
  final double originScale;

  /// Quanto da nervura-rota já foi desenhado (0–1), do pino até o caule.
  final double reveal;
  final double stemOpacity;
  final double destScale;
  final double glow;

  static const rest = LeafFrame();

  // Curvas do arquivo de design (CSS cubic-bezier).
  static const _spring = Cubic(0.3, 1.3, 0.5, 1);
  static const _sunCurve = Cubic(0.22, 0.8, 0.26, 1);

  /// Quadro no instante [t] do ciclo de 5,5 s (0–1), com as mesmas
  /// keyframes da animação do anexo.
  static LeafFrame at(double t) => LeafFrame(
        leafTurnDeg: _kf(t, const [(0, 30), (.18, -6), (.26, 3), (.34, 0), (.60, 0), (.70, -3), (.80, 0)], _spring),
        leafScale: _kf(t, const [(0, 0), (.18, 1.04), (.26, 1)], _spring),
        leafOpacity: _kf(t, const [(0, 0), (.18, 1), (.94, 1), (1, 0)], _spring).clamp(0, 1),
        sunOffset: Offset(
          _kf(t, const [(0, -10), (.14, -10), (.34, 0)], _sunCurve),
          _kf(t, const [(0, 18), (.14, 18), (.34, 0)], _sunCurve),
        ),
        sunOpacity: _kf(t, const [(0, 0), (.14, 0), (.34, 1), (.94, 1), (1, 0)], _sunCurve).clamp(0, 1),
        originScale: _kf(t, const [(0, 0), (.32, 0), (.38, 1)], _spring),
        reveal: _kf(t, const [(0, 0), (.38, 0), (.62, 1)], Curves.easeInOut),
        stemOpacity: _kf(t, const [(0, 0), (.60, 0), (.66, 1), (.94, 1), (1, 0)], _spring).clamp(0, 1),
        destScale: _kf(t, const [(0, 0), (.64, 0), (.70, 1.5), (.76, 1)], _spring),
        glow: _kf(t, const [(0, .3), (.34, 1), (.94, 1), (1, .3)], _spring).clamp(0, 1),
      );

  static double _kf(double t, List<(double, double)> frames, Curve curve) {
    if (t <= frames.first.$1) return frames.first.$2;
    for (var i = 1; i < frames.length; i++) {
      final (t1, v1) = frames[i];
      if (t <= t1) {
        final (t0, v0) = frames[i - 1];
        final f = curve.transform((t - t0) / (t1 - t0));
        return v0 + (v1 - v0) * f;
      }
    }
    return frames.last.$2;
  }
}

/// Pinta o ícone. Sem fundo ([background] = false), a folha fica sobre a
/// superfície da tela; em superfície clara ([onLight]) ganha contorno verde
/// e o caule fica verde, para não sumir no branco.
class LeafIconPainter extends CustomPainter {
  LeafIconPainter({
    this.variant = LeafVariant.padrao,
    this.frame = LeafFrame.rest,
    this.background = true,
    this.rounded = true,
    this.onLight = false,
    this.silhouette = false,
    this.contentScale = 1,
    super.repaint,
  });

  final LeafVariant variant;
  final LeafFrame frame;
  final bool background;

  /// Cantos arredondados do quadro (o iOS e as lojas querem o quadrado cheio).
  final bool rounded;
  final bool onLight;

  /// Só a forma, em branco, para o ícone temático (monocromático) do Android.
  final bool silhouette;

  /// Encolhe o desenho no centro: o ícone adaptativo do Android mostra só os
  /// 72 dp do meio de um quadro de 108 dp.
  final double contentScale;

  static const _edge = Color(0xFF178A6E);

  static final _leaf = Path()
    ..moveTo(50, 12)
    ..cubicTo(73, 30, 73, 64, 50, 84)
    ..cubicTo(27, 64, 27, 30, 50, 12)
    ..close();
  static const _leafBox = Rect.fromLTRB(32.75, 12, 67.25, 84);

  static final _clipLeft = Path()
    ..moveTo(50, 0)
    ..lineTo(50, 20)
    ..cubicTo(46, 40, 54, 58, 50, 80)
    ..lineTo(50, 100)
    ..lineTo(0, 100)
    ..lineTo(0, 0)
    ..close();
  static final _clipRight = Path()
    ..moveTo(50, 0)
    ..lineTo(50, 20)
    ..cubicTo(46, 40, 54, 58, 50, 80)
    ..lineTo(50, 100)
    ..lineTo(100, 100)
    ..lineTo(100, 0)
    ..close();
  static final _vein = Path()
    ..moveTo(50, 20)
    ..cubicTo(46, 40, 54, 58, 50, 80);
  static final _stem = Path()
    ..moveTo(50, 84)
    ..cubicTo(51, 90, 55, 93, 61, 94);

  @override
  void paint(Canvas canvas, Size size) {
    final p = LeafPalette.of(variant);
    final f = frame;
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    if (contentScale != 1) {
      canvas
        ..translate(50, 50)
        ..scale(contentScale)
        ..translate(-50, -50);
    }

    const full = Rect.fromLTWH(0, 0, 100, 100);
    final frameShape = RRect.fromRectAndRadius(full, Radius.circular(rounded ? 22.5 : 0));
    // Fora do quadro arredondado (ou além dos 100, no Android), as cores se estendem.
    final bgArea = contentScale < 1 ? const Rect.fromLTWH(-100, -100, 300, 300) : full;

    if (background && !silhouette) {
      void fill(Shader shader) {
        final paint = Paint()..shader = shader;
        contentScale < 1 ? canvas.drawRect(bgArea, paint) : canvas.drawRRect(frameShape, paint);
      }

      fill(LinearGradient(
        begin: Alignment.topLeft,
        end: const Alignment(-0.4, 1),
        colors: p.bg,
        stops: p.bgStops,
      ).createShader(full));
      fill(RadialGradient(
        center: const Alignment(-0.9, 1),
        radius: 0.75,
        colors: [p.glow2.withValues(alpha: p.glow2Alpha), p.glow2.withValues(alpha: 0)],
      ).createShader(full));
      fill(RadialGradient(
        center: const Alignment(0.8, -0.9),
        radius: 0.8,
        colors: [for (final a in p.glowAlpha) p.glow.withValues(alpha: a * f.glow)],
        stops: const [0, 0.45, 1],
      ).createShader(full));
    }

    // Marca: no arquivo de design, translate(14 14) scale(0.72).
    canvas
      ..save()
      ..translate(14, 14)
      ..scale(0.72);
    _paintMark(canvas, p);
    canvas.restore();

    if (background && !silhouette) {
      final hi = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [const Color(0xFFFFFFFF).withValues(alpha: p.highlightAlpha), const Color(0x00FFFFFF)],
          stops: const [0, 0.35],
        ).createShader(full);
      contentScale < 1 ? canvas.drawRect(bgArea, hi) : canvas.drawRRect(frameShape, hi);
    }
    canvas.restore();
  }

  void _paintMark(Canvas canvas, LeafPalette p) {
    final f = frame;
    const white = Color(0xFFFFFFFF);
    final stemColor = silhouette ? white : (onLight && !background ? _edge : p.stem);

    // Sol.
    if (f.sunOpacity > 0) {
      final c = const Offset(77, 24) + f.sunOffset;
      final rect = Rect.fromCircle(center: c, radius: 13);
      final paint = Paint()
        ..shader = silhouette
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: const Alignment(0.8, 1),
                colors: [for (final s in p.sun) s.withValues(alpha: f.sunOpacity)],
              ).createShader(rect);
      if (silhouette) paint.color = white;
      canvas.drawCircle(c, 13, paint);
    }

    // Folha inclinada 24° em volta da base (50, 84); brota e balança dali.
    if (f.leafOpacity > 0 && f.leafScale > 0) {
      canvas
        ..save()
        ..translate(50, 84)
        ..rotate((-24 + f.leafTurnDeg) * math.pi / 180)
        ..scale(f.leafScale)
        ..translate(-50, -84);
      if (f.leafOpacity < 1) canvas.saveLayer(null, Paint()..color = white.withValues(alpha: f.leafOpacity));
      if (silhouette) canvas.saveLayer(null, Paint());

      void half(Path clip, double dx, List<Color> colors) {
        canvas
          ..save()
          ..translate(dx, 0)
          ..clipPath(clip);
        final paint = Paint();
        if (silhouette) {
          paint.color = white;
        } else {
          paint.shader = LinearGradient(begin: Alignment.topLeft, end: const Alignment(0.6, 1), colors: colors)
              .createShader(_leafBox);
        }
        canvas.drawPath(_leaf, paint);
        if (onLight && !background && !silhouette) {
          canvas.drawPath(
            _leaf,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.6
              ..strokeJoin = StrokeJoin.round
              ..color = _edge,
          );
        }
        canvas.restore();
      }

      half(_clipLeft, -1.3, p.leafLeft);
      half(_clipRight, 1.3, p.leafRight);

      // No ícone temático, a rota e o pino são recortes na folha.
      final ink = Paint()..color = p.ink;
      if (silhouette) ink.blendMode = BlendMode.clear;
      if (f.reveal > 0) _dots(canvas, _vein.computeMetrics().first, f.reveal, ink);
      if (f.originScale > 0) {
        canvas.drawCircle(
          const Offset(50, 20),
          3.2 * f.originScale,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.2 * f.originScale
            ..color = p.ink
            ..blendMode = silhouette ? BlendMode.clear : BlendMode.srcOver,
        );
      }
      if (silhouette) canvas.restore();
      if (f.leafOpacity < 1) canvas.restore();
      canvas.restore();
    }

    // Caule e destino (fora da rotação, como no arquivo de design).
    if (f.stemOpacity > 0) {
      canvas.drawPath(
        _stem,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.6
          ..strokeCap = StrokeCap.round
          ..color = stemColor.withValues(alpha: f.stemOpacity),
      );
    }
    if (f.destScale > 0) {
      canvas.drawCircle(const Offset(62, 94), 3.6 * f.destScale, Paint()..color = stemColor);
    }
  }

  /// Rota pontilhada: um ponto de 2,4 a cada 4,4 unidades, do pino ao caule.
  void _dots(Canvas canvas, PathMetric m, double reveal, Paint paint) {
    final end = m.length * reveal;
    for (var d = 0.0; d <= end + 0.01; d += 4.4) {
      canvas.drawCircle(m.getTangentForOffset(d)!.position, 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(LeafIconPainter old) =>
      old.variant != variant ||
      old.frame != frame ||
      old.background != background ||
      old.onLight != onLight ||
      old.rounded != rounded ||
      old.silhouette != silhouette ||
      old.contentScale != contentScale;
}
