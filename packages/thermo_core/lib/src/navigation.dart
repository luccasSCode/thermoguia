import 'dart:math' as math;

import 'geo.dart';

/// Rumo de [a] para [b], em graus (0 = norte, 90 = leste).
double bearingDeg(GeoPoint a, GeoPoint b) {
  final la1 = a.lat * math.pi / 180, la2 = b.lat * math.pi / 180;
  final dLng = (b.lng - a.lng) * math.pi / 180;
  final y = math.sin(dLng) * math.cos(la2);
  final x = math.cos(la1) * math.sin(la2) - math.sin(la1) * math.cos(la2) * math.cos(dLng);
  return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
}

/// Ponto a [meters] de [p] na direção [bearing] (aproximação plana, ok até ~1 km).
GeoPoint offsetPoint(GeoPoint p, double bearing, double meters) {
  final r = bearing * math.pi / 180;
  final dLat = meters * math.cos(r) / 110540;
  final dLng = meters * math.sin(r) / (111320 * math.cos(p.lat * math.pi / 180));
  return GeoPoint(p.lat + dLat, p.lng + dLng);
}

/// Diferença de ângulo em (-180, 180]. Positivo = [to] fica à direita de [from].
double angleDiff(double from, double to) {
  final d = (to - from) % 360;
  return d > 180 ? d - 360 : d;
}

/// Lado da rua (em relação ao sentido de quem anda).
enum Side {
  esquerdo('esquerdo'),
  direito('direito');

  const Side(this.label);
  final String label;

  static Side? fromName(String? s) => s == null ? null : values.where((v) => v.name == s).firstOrNull;
}

/// Manobra de navegação, no vocabulário do OSRM
/// (http://project-osrm.org/docs/v5.24.0/api/#stepmaneuver-object).
class Maneuver {
  const Maneuver({
    required this.type,
    required this.modifier,
    required this.street,
    required this.point,
    required this.along,
    this.exit,
  });

  /// depart, turn, new name, continue, merge, fork, end of road, roundabout,
  /// rotary, roundabout turn, exit roundabout, arrive...
  final String type;

  /// left, right, slight left, slight right, sharp left, sharp right, straight, uturn.
  final String modifier;

  /// Rua em que a pessoa entra depois da manobra ('' se sem nome).
  final String street;
  final GeoPoint point;

  /// Distância, em metros, do início da rota até a manobra.
  final double along;

  /// Saída da rotatória (1, 2, 3...).
  final int? exit;

  bool get isArrival => type == 'arrive';

  factory Maneuver.fromJson(Map<String, dynamic> j) => Maneuver(
        type: j['type'] as String,
        modifier: j['modifier'] as String? ?? '',
        street: j['street'] as String? ?? '',
        point: GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        along: (j['along'] as num).toDouble(),
        exit: (j['exit'] as num?)?.toInt(),
      );

  Map<String, dynamic> toJson() => {
        'type': type,
        'modifier': modifier,
        'street': street,
        'lat': double.parse(point.lat.toStringAsFixed(6)),
        'lng': double.parse(point.lng.toStringAsFixed(6)),
        'along': along.round(),
        if (exit != null) 'exit': exit,
      };

  /// Instrução curta, para o painel e para a voz.
  String get instruction {
    final into = street.isEmpty ? '' : ' na $street';
    final onto = street.isEmpty ? '' : ' pela $street';
    String turn(String m) => switch (m) {
          'left' => 'Vire à esquerda',
          'right' => 'Vire à direita',
          'slight left' => 'Mantenha-se à esquerda',
          'slight right' => 'Mantenha-se à direita',
          'sharp left' => 'Vire acentuadamente à esquerda',
          'sharp right' => 'Vire acentuadamente à direita',
          'uturn' => 'Faça o retorno',
          _ => 'Siga em frente',
        };
    return switch (type) {
      'depart' => street.isEmpty ? 'Comece o trajeto' : 'Siga$onto',
      'arrive' => 'Você chegou ao destino',
      'roundabout' || 'rotary' => exit == null
          ? 'Entre na rotatória$onto'
          : 'Na rotatória, pegue a ${exit}ª saída${street.isEmpty ? '' : ' para a $street'}',
      'exit roundabout' || 'exit rotary' => 'Saia da rotatória$onto',
      'fork' => '${modifier.contains('left') ? 'Na bifurcação, mantenha-se à esquerda' : 'Na bifurcação, mantenha-se à direita'}$onto',
      'end of road' => '${modifier.contains('left') ? 'No fim da rua, vire à esquerda' : 'No fim da rua, vire à direita'}$into',
      'new name' || 'continue' when modifier == 'straight' || modifier.isEmpty => 'Continue em frente$onto',
      _ => '${turn(modifier)}$into',
    };
  }
}

/// Aviso ao longo da rota (sol forte, lado com sombra, relato, ponto de água...).
class RouteAlert {
  const RouteAlert({
    required this.kind,
    required this.message,
    required this.point,
    required this.along,
    this.length = 0,
    this.side,
  });

  /// sol_forte, sombra, lado_sombra, refresco, ou o tipo de um relato da
  /// comunidade (sem_sombra, calor_extremo, alagamento, transito, obra...).
  final String kind;
  final String message;
  final GeoPoint point;
  final double along;

  /// Extensão do trecho afetado, em metros (0 = ponto).
  final double length;
  final Side? side;

  factory RouteAlert.fromJson(Map<String, dynamic> j) => RouteAlert(
        kind: j['kind'] as String,
        message: j['message'] as String,
        point: GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
        along: (j['along'] as num).toDouble(),
        length: (j['length'] as num?)?.toDouble() ?? 0,
        side: Side.fromName(j['side'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'message': message,
        'lat': double.parse(point.lat.toStringAsFixed(6)),
        'lng': double.parse(point.lng.toStringAsFixed(6)),
        'along': along.round(),
        if (length > 0) 'length': length.round(),
        if (side != null) 'side': side!.name,
      };
}

/// Posição projetada sobre a rota.
class RouteFix {
  const RouteFix({required this.along, required this.offset, required this.segment, required this.snapped});

  /// Metros percorridos desde o início da rota.
  final double along;

  /// Distância, em metros, entre a pessoa e a linha da rota.
  final double offset;
  final int segment;
  final GeoPoint snapped;
}

/// Linha da rota com distâncias acumuladas, para projetar a posição do GPS.
class RouteLine {
  RouteLine(this.points) : cumulative = _cumulative(points);

  final List<GeoPoint> points;
  final List<double> cumulative;

  double get length => cumulative.isEmpty ? 0 : cumulative.last;

  static List<double> _cumulative(List<GeoPoint> pts) {
    final out = <double>[0];
    for (var i = 1; i < pts.length; i++) {
      out.add(out.last + distanceMeters(pts[i - 1], pts[i]));
    }
    return out;
  }

  /// Projeta [p] na rota. Com [hint] (último segmento conhecido), procura
  /// só por perto, para não "pular" para um trecho que passa ao lado.
  RouteFix project(GeoPoint p, {int? hint, int window = 40}) {
    if (points.length < 2) {
      return RouteFix(along: 0, offset: points.isEmpty ? 0 : distanceMeters(p, points.first), segment: 0, snapped: points.isEmpty ? p : points.first);
    }
    final from = hint == null ? 0 : math.max(0, hint - 3);
    final to = hint == null ? points.length - 1 : math.min(points.length - 1, hint + window);
    final cosLat = math.cos(p.lat * math.pi / 180);
    (double, double) xy(GeoPoint q) => ((q.lng - p.lng) * 111320 * cosLat, (q.lat - p.lat) * 110540);

    RouteFix? best;
    for (var i = from; i < to; i++) {
      final (ax, ay) = xy(points[i]);
      final (bx, by) = xy(points[i + 1]);
      final dx = bx - ax, dy = by - ay;
      final len2 = dx * dx + dy * dy;
      final t = len2 == 0 ? 0.0 : (-(ax * dx + ay * dy) / len2).clamp(0.0, 1.0);
      final cx = ax + t * dx, cy = ay + t * dy;
      final off = math.sqrt(cx * cx + cy * cy);
      if (best == null || off < best.offset) {
        final seg = cumulative[i + 1] - cumulative[i];
        best = RouteFix(
          along: cumulative[i] + t * seg,
          offset: off,
          segment: i,
          snapped: lerpPoint(points[i], points[i + 1], t),
        );
      }
    }
    return best!;
  }

  /// Ponto e rumo da rota a [along] metros do início.
  (GeoPoint, double) at(double along) {
    if (points.length < 2) return (points.first, 0);
    final a = along.clamp(0.0, length);
    var i = 0;
    while (i < cumulative.length - 2 && cumulative[i + 1] < a) {
      i++;
    }
    final seg = cumulative[i + 1] - cumulative[i];
    final t = seg == 0 ? 0.0 : (a - cumulative[i]) / seg;
    return (lerpPoint(points[i], points[i + 1], t), bearingDeg(points[i], points[i + 1]));
  }
}

/// "Em 50 metros", "Em 1,2 quilômetro" — arredondado como na fala.
String spokenDistance(double meters) {
  if (meters >= 1000) {
    final km = (meters / 100).round() / 10;
    return 'Em ${km.toStringAsFixed(km == km.roundToDouble() ? 0 : 1).replaceAll('.', ',')} ${km == 1 ? 'quilômetro' : 'quilômetros'}';
  }
  final step = meters > 200 ? 50 : 10;
  final m = math.max(step, (meters / step).round() * step);
  return 'Em $m metros';
}

/// Trechos contínuos onde [test] vale por pelo menos [minM] metros.
/// Devolve pares (início, fim) em índices de [line].
List<(int, int)> runsWhere(RouteLine line, List<bool> test, {double minM = 60}) {
  final out = <(int, int)>[];
  int? start;
  for (var i = 0; i <= test.length; i++) {
    final on = i < test.length && test[i];
    if (on && start == null) start = i;
    if (!on && start != null) {
      final end = i - 1;
      if (line.cumulative[end] - line.cumulative[start] >= minM) out.add((start, end));
      start = null;
    }
  }
  return out;
}
