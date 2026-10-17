import 'package:flutter/material.dart';
import 'package:thermo_core/thermo_core.dart';

import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Faixa térmica: do azul do rio ao laranja do sol, como no escudo da logo.
/// O marcador mostra onde o usuário está agora. No Modo Sol Forte vira
/// blocos sólidos de alto contraste.
class HeatBand extends StatelessWidget {
  const HeatBand({super.key, required this.score, required this.level, this.height = 18});
  final int score;
  final RiskLevel level;
  final double height;

  @override
  Widget build(BuildContext context) {
    final sun = context.sunMode;
    return Semantics(
      label: 'Risco ${level.label}, $score de 100',
      child: SizedBox(
        height: height + 14,
        child: CustomPaint(
          painter: _BandPainter(score / 100, sun, Theme.of(context).colorScheme.onSurface),
          size: Size.infinite,
        ),
      ),
    );
  }
}

class _BandPainter extends CustomPainter {
  _BandPainter(this.t, this.sunMode, this.ink);
  final double t;
  final bool sunMode;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final barH = size.height - 14;
    final rect = Rect.fromLTWH(0, 7, size.width, barH);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(barH / 2));

    if (sunMode) {
      final colors = RiskLevel.values.map((l) => Tokens.risk(l, sunMode: true)).toList();
      final w = size.width / colors.length;
      canvas.save();
      canvas.clipRRect(rr);
      for (var i = 0; i < colors.length; i++) {
        canvas.drawRect(Rect.fromLTWH(i * w, rect.top, w + 1, barH), Paint()..color = colors[i]);
      }
      canvas.restore();
      canvas.drawRRect(rr, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.black);
    } else {
      canvas.drawRRect(
        rr,
        Paint()
          ..shader = const LinearGradient(
            colors: [Tokens.rio, Color(0xFF8C8FA0), Tokens.sol, Color(0xFFA8231F)],
            stops: [0, 0.35, 0.7, 1],
          ).createShader(rect),
      );
    }

    final x = (t.clamp(0.0, 1.0)) * (size.width - barH) + barH / 2;
    final center = Offset(x, rect.center.dy);
    canvas.drawCircle(center, barH / 2 + 6, Paint()..color = Colors.white);
    canvas.drawCircle(center, barH / 2 + 6, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = sunMode ? 3 : 2
      ..color = ink);
  }

  @override
  bool shouldRepaint(_BandPainter old) => old.t != t || old.sunMode != sunMode || old.ink != ink;
}
