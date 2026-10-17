import 'package:latlong2/latlong.dart';
import 'package:thermo_core/thermo_core.dart';

class Place {
  const Place({required this.name, required this.lat, required this.lng, this.address = '', this.savedAs});
  final String name;
  final String address;
  final double lat;
  final double lng;

  /// Rótulo de favorito ("Casa", "Trabalho"), se salvo.
  final String? savedAs;

  LatLng get latLng => LatLng(lat, lng);
  GeoPoint get geo => GeoPoint(lat, lng);

  factory Place.fromJson(Map<String, dynamic> j) => Place(
        name: j['name'] as String,
        address: j['address'] as String? ?? '',
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        savedAs: j['savedAs'] as String?,
      );

  Map<String, dynamic> toJson() =>
      {'name': name, 'address': address, 'lat': lat, 'lng': lng, 'savedAs': savedAs};
}

class RouteOption {
  const RouteOption({
    required this.id,
    required this.label,
    required this.tags,
    required this.recommended,
    required this.distanceM,
    required this.durationS,
    required this.shadeScore,
    required this.sunExposureMin,
    required this.thermalLoad,
    required this.points,
    required this.shade,
    this.maneuvers = const [],
    this.alerts = const [],
  });

  final String id;
  final String label;
  final List<String> tags;
  final bool recommended;
  final double distanceM;
  final double durationS;
  final double shadeScore;
  final double sunExposureMin;
  final double thermalLoad;
  final List<LatLng> points;
  final List<double> shade;

  /// Manobras (vire à direita...) e avisos do caminho, para a navegação.
  final List<Maneuver> maneuvers;
  final List<RouteAlert> alerts;

  factory RouteOption.fromJson(Map<String, dynamic> j) {
    final pts = (j['points'] as List).cast<List>();
    return RouteOption(
      id: j['id'] as String,
      label: j['label'] as String,
      tags: (j['tags'] as List).cast<String>(),
      recommended: j['recommended'] as bool? ?? false,
      distanceM: (j['distanceM'] as num).toDouble(),
      durationS: (j['durationS'] as num).toDouble(),
      shadeScore: (j['shadeScore'] as num).toDouble(),
      sunExposureMin: (j['sunExposureMin'] as num).toDouble(),
      thermalLoad: (j['thermalLoad'] as num).toDouble(),
      points: pts.map((p) => LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble())).toList(),
      shade: pts.map((p) => (p[2] as num).toDouble()).toList(),
      maneuvers: (j['maneuvers'] as List? ?? const [])
          .map((m) => Maneuver.fromJson((m as Map).cast<String, dynamic>()))
          .toList(),
      alerts: (j['alerts'] as List? ?? const [])
          .map((a) => RouteAlert.fromJson((a as Map).cast<String, dynamic>()))
          .toList(),
    );
  }
}

class RoutesResult {
  const RoutesResult({required this.routes, required this.advice, required this.climate, required this.greenReady});
  final List<RouteOption> routes;
  final String advice;
  final ClimateSnapshot climate;
  final bool greenReady;
}

class Oasis {
  const Oasis({required this.kind, required this.name, required this.lat, required this.lng, required this.distanceM});
  final String kind;
  final String name;
  final double lat;
  final double lng;
  final int distanceM;

  LatLng get latLng => LatLng(lat, lng);

  factory Oasis.fromJson(Map<String, dynamic> j) => Oasis(
        kind: j['kind'] as String,
        name: j['name'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        distanceM: (j['distanceM'] as num).toInt(),
      );
}

enum ReportKind {
  sombraBoa('sombra_boa', 'Boa sombra aqui'),
  semSombra('sem_sombra', 'Trecho sem sombra'),
  bebedouro('bebedouro', 'Água disponível'),
  calorExtremo('calor_extremo', 'Calor extremo agora'),
  alagamento('alagamento', 'Alagamento'),
  transito('transito', 'Trânsito intenso'),
  obra('obra', 'Obra ou calçada bloqueada');

  const ReportKind(this.api, this.label);
  final String api;
  final String label;

  static ReportKind fromApi(String s) => values.firstWhere((k) => k.api == s, orElse: () => sombraBoa);
}

class CommunityReport {
  const CommunityReport(this.kind, this.lat, this.lng, this.note);
  final ReportKind kind;
  final double lat;
  final double lng;
  final String note;

  LatLng get latLng => LatLng(lat, lng);

  factory CommunityReport.fromJson(Map<String, dynamic> j) => CommunityReport(
        ReportKind.fromApi(j['kind'] as String),
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
        j['note'] as String? ?? '',
      );
}
