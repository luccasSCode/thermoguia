import 'dart:math' as math;

/// Índice de calor (sensação térmica por calor + umidade) em °C.
///
/// Implementa a regressão de Rothfusz usada pelo NOAA/NWS, com os
/// ajustes para umidade muito baixa ou muito alta.
double heatIndexC(double tempC, double humidity) {
  final t = tempC * 9 / 5 + 32;
  final rh = humidity.clamp(0, 100).toDouble();

  var hi = 0.5 * (t + 61.0 + ((t - 68.0) * 1.2) + (rh * 0.094));
  if ((hi + t) / 2 >= 80) {
    hi = -42.379 +
        2.04901523 * t +
        10.14333127 * rh -
        0.22475541 * t * rh -
        0.00683783 * t * t -
        0.05481717 * rh * rh +
        0.00122874 * t * t * rh +
        0.00085282 * t * rh * rh -
        0.00000199 * t * t * rh * rh;
    if (rh < 13 && t >= 80 && t <= 112) {
      hi -= ((13 - rh) / 4) * math.sqrt((17 - (t - 95).abs()) / 17);
    } else if (rh > 85 && t >= 80 && t <= 87) {
      hi += ((rh - 85) / 10) * ((87 - t) / 5);
    }
  }
  return (hi - 32) * 5 / 9;
}
