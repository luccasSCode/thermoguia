import 'dart:math' as math;

class SunPosition {
  const SunPosition(this.elevationDeg, this.azimuthDeg);

  /// Altura do sol acima do horizonte (graus). Negativo = noite.
  final double elevationDeg;

  /// Azimute a partir do norte, sentido horário (graus).
  final double azimuthDeg;

  bool get isUp => elevationDeg > 0;

  /// Sol baixo projeta sombras longas de prédios e árvores.
  bool get castsLongShadows => elevationDeg > 0 && elevationDeg < 25;
}

/// Posição aproximada do sol (algoritmo simplificado do NOAA, erro < 1°).
SunPosition sunPosition(double lat, double lng, DateTime time) {
  final t = time.toUtc();
  final dayOfYear = t.difference(DateTime.utc(t.year, 1, 1)).inDays + 1;
  final hour = t.hour + t.minute / 60 + t.second / 3600;
  final g = 2 * math.pi / 365 * (dayOfYear - 1 + (hour - 12) / 24);

  final eqTime = 229.18 *
      (0.000075 +
          0.001868 * math.cos(g) -
          0.032077 * math.sin(g) -
          0.014615 * math.cos(2 * g) -
          0.040849 * math.sin(2 * g));
  final decl = 0.006918 -
      0.399912 * math.cos(g) +
      0.070257 * math.sin(g) -
      0.006758 * math.cos(2 * g) +
      0.000907 * math.sin(2 * g) -
      0.002697 * math.cos(3 * g) +
      0.00148 * math.sin(3 * g);

  final trueSolarMin = hour * 60 + eqTime + 4 * lng;
  final ha = (trueSolarMin / 4 - 180) * math.pi / 180;
  final latR = lat * math.pi / 180;

  final cosZen = math.sin(latR) * math.sin(decl) +
      math.cos(latR) * math.cos(decl) * math.cos(ha);
  final zen = math.acos(cosZen.clamp(-1.0, 1.0));
  final elevation = 90 - zen * 180 / math.pi;

  final az = math.atan2(
    math.sin(ha),
    math.cos(ha) * math.sin(latR) - math.tan(decl) * math.cos(latR),
  );
  final azimuth = (az * 180 / math.pi + 180) % 360;
  return SunPosition(elevation, azimuth);
}
