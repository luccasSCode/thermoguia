import 'dart:math' as math;

class GeoPoint {
  const GeoPoint(this.lat, this.lng);
  final double lat;
  final double lng;

  factory GeoPoint.fromJson(Map<String, dynamic> j) =>
      GeoPoint((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble());
  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng};

  @override
  String toString() => '($lat, $lng)';
}

/// Distância em metros (Haversine).
double distanceMeters(GeoPoint a, GeoPoint b) {
  const r = 6371000.0;
  final dLat = _rad(b.lat - a.lat);
  final dLng = _rad(b.lng - a.lng);
  final h = math.pow(math.sin(dLat / 2), 2) +
      math.cos(_rad(a.lat)) *
          math.cos(_rad(b.lat)) *
          math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(h)));
}

/// Interpola linearmente entre dois pontos (t de 0 a 1).
GeoPoint lerpPoint(GeoPoint a, GeoPoint b, double t) =>
    GeoPoint(a.lat + (b.lat - a.lat) * t, a.lng + (b.lng - a.lng) * t);

/// Retângulo geográfico (usado para delimitar cidades atendidas).
class GeoBounds {
  const GeoBounds(this.south, this.west, this.north, this.east);
  final double south, west, north, east;

  bool contains(GeoPoint p) =>
      p.lat >= south && p.lat <= north && p.lng >= west && p.lng <= east;

  Map<String, dynamic> toJson() =>
      {'south': south, 'west': west, 'north': north, 'east': east};
}

double _rad(double deg) => deg * math.pi / 180;
