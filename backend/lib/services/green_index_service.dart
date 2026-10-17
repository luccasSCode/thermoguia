import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:thermo_core/thermo_core.dart';

import '../cities.dart';
import '../config.dart';

/// Ponto de refresco ("Oásis"): lugar para se abrigar ou se hidratar.
class Oasis {
  const Oasis(this.id, this.kind, this.name, this.point);
  final String id;
  final String kind; // bebedouro, shopping, farmacia, supermercado, biblioteca, parque
  final String name;
  final GeoPoint point;
}

/// Índice de cobertura verde de uma cidade, em grade de ~45 m.
///
/// Fonte: OpenStreetMap via Overpass (árvores, fileiras de árvores, parques,
/// matas). O resultado bruto fica em cache em disco por 30 dias.
/// Evolução prevista: somar o NDVI do Sentinel-2 para medir a copa real.
class GreenIndexService {
  GreenIndexService(this._config, this._client, this.city);

  final Config _config;
  final http.Client _client;
  final City city;

  static const cellDeg = 0.0004;
  final _canopy = <int, double>{};
  final oases = <Oasis>[];
  bool ready = false;

  int _i(double lat) => ((lat - city.bounds.south) / cellDeg).floor();
  int _j(double lng) => ((lng - city.bounds.west) / cellDeg).floor();
  int _key(int i, int j) => i * 100000 + j;

  GeoPoint _center(int key) {
    final i = key ~/ 100000, j = key % 100000;
    return GeoPoint(
      city.bounds.south + (i + 0.5) * cellDeg,
      city.bounds.west + (j + 0.5) * cellDeg,
    );
  }

  /// Carrega em segundo plano. Enquanto não estiver pronto, as rotas
  /// usam apenas a geometria solar.
  Future<void> init() async {
    try {
      final raw = await _loadRaw();
      _build(raw);
      ready = true;
      stdout.writeln('[verde] ${city.name}: ${_canopy.length} células, ${oases.length} oásis');
    } catch (e) {
      stderr.writeln('[verde] Falha ao carregar índice de ${city.name}: $e');
    }
  }

  Future<Map<String, dynamic>> _loadRaw() async {
    final dir = Directory(_config.cacheDir)..createSync(recursive: true);
    final file = File('${dir.path}/overpass_${city.id}.json');
    if (file.existsSync() &&
        DateTime.now().difference(file.lastModifiedSync()).inDays < 30) {
      return jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    }
    final b = city.bounds;
    final bbox = '${b.south},${b.west},${b.north},${b.east}';
    final query = '''
[out:json][timeout:180];
(
  node["natural"="tree"]($bbox);
  way["natural"="tree_row"]($bbox);
  way["leisure"="park"]($bbox);
  relation["leisure"="park"]($bbox);
  way["natural"="wood"]($bbox);
  relation["natural"="wood"]($bbox);
  way["landuse"="forest"]($bbox);
  relation["landuse"="forest"]($bbox);
  node["amenity"="drinking_water"]($bbox);
  nwr["shop"="mall"]($bbox);
  node["amenity"="pharmacy"]($bbox);
  nwr["shop"="supermarket"]($bbox);
  nwr["amenity"="library"]($bbox);
);
out geom;
''';
    stdout.writeln('[verde] Baixando dados do OpenStreetMap para ${city.name}...');
    final res = await _client.post(
      Uri.parse(_config.overpassUrl),
      headers: {'User-Agent': _config.userAgent},
      body: {'data': query},
    ).timeout(const Duration(minutes: 4));
    if (res.statusCode != 200) {
      throw HttpException('Overpass respondeu ${res.statusCode}');
    }
    await file.writeAsString(res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  void _build(Map<String, dynamic> raw) {
    final elements = (raw['elements'] as List).cast<Map<String, dynamic>>();
    for (final el in elements) {
      final tags = (el['tags'] as Map?)?.cast<String, dynamic>() ?? const {};
      final type = el['type'];
      final id = '${type}_${el['id']}';

      if (type == 'node' && tags['natural'] == 'tree') {
        _addPoint((el['lat'] as num).toDouble(), (el['lon'] as num).toDouble(), 0.35);
        continue;
      }
      if (type == 'way' && tags['natural'] == 'tree_row') {
        for (final p in _geometry(el['geometry'])) {
          _addPoint(p.lat, p.lng, 0.25);
        }
        continue;
      }

      final areaValue = switch (tags) {
        {'natural': 'wood'} || {'landuse': 'forest'} => 1.0,
        {'leisure': 'park'} => 0.6,
        _ => 0.0,
      };
      if (areaValue > 0) {
        for (final ring in _rings(el)) {
          _rasterize(ring, areaValue);
        }
      }

      final kind = switch (tags) {
        {'amenity': 'drinking_water'} => 'bebedouro',
        {'shop': 'mall'} => 'shopping',
        {'amenity': 'pharmacy'} => 'farmacia',
        {'shop': 'supermarket'} => 'supermercado',
        {'amenity': 'library'} => 'biblioteca',
        {'leisure': 'park'} => 'parque',
        _ => null,
      };
      if (kind != null) {
        final p = _elementCenter(el);
        if (p != null) {
          oases.add(Oasis(id, kind, (tags['name'] as String?) ?? _defaultName(kind), p));
        }
      }
    }
  }

  String _defaultName(String kind) => switch (kind) {
        'bebedouro' => 'Bebedouro',
        'shopping' => 'Shopping',
        'farmacia' => 'Farmácia',
        'supermercado' => 'Supermercado',
        'biblioteca' => 'Biblioteca',
        _ => 'Parque',
      };

  List<GeoPoint> _geometry(Object? g) => (g as List? ?? const [])
      .cast<Map<String, dynamic>>()
      .map((p) => GeoPoint((p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()))
      .toList();

  Iterable<List<GeoPoint>> _rings(Map<String, dynamic> el) sync* {
    if (el['type'] == 'way') {
      yield _geometry(el['geometry']);
    } else if (el['type'] == 'relation') {
      for (final m in (el['members'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        if (m['role'] == 'outer' && m['geometry'] != null) yield _geometry(m['geometry']);
      }
    }
  }

  GeoPoint? _elementCenter(Map<String, dynamic> el) {
    if (el['lat'] != null) {
      return GeoPoint((el['lat'] as num).toDouble(), (el['lon'] as num).toDouble());
    }
    final pts = _rings(el).expand((r) => r).toList();
    if (pts.isEmpty) return null;
    return GeoPoint(
      pts.map((p) => p.lat).reduce((a, b) => a + b) / pts.length,
      pts.map((p) => p.lng).reduce((a, b) => a + b) / pts.length,
    );
  }

  void _addPoint(double lat, double lng, double v) {
    final k = _key(_i(lat), _j(lng));
    _canopy[k] = (_canopy[k] ?? 0) + v;
  }

  void _rasterize(List<GeoPoint> ring, double value) {
    if (ring.length < 3) return;
    final i0 = _i(ring.map((p) => p.lat).reduce(math.min));
    final i1 = _i(ring.map((p) => p.lat).reduce(math.max));
    final j0 = _j(ring.map((p) => p.lng).reduce(math.min));
    final j1 = _j(ring.map((p) => p.lng).reduce(math.max));
    if ((i1 - i0 + 1) * (j1 - j0 + 1) > 250000) return; // área gigante: ignora
    for (var i = i0; i <= i1; i++) {
      for (var j = j0; j <= j1; j++) {
        final k = _key(i, j);
        if (_inside(_center(k), ring)) {
          _canopy[k] = math.max(_canopy[k] ?? 0, value);
        }
      }
    }
  }

  bool _inside(GeoPoint p, List<GeoPoint> ring) {
    var inside = false;
    for (var a = 0, b = ring.length - 1; a < ring.length; b = a++) {
      final pa = ring[a], pb = ring[b];
      if ((pa.lat > p.lat) != (pb.lat > p.lat) &&
          p.lng < (pb.lng - pa.lng) * (p.lat - pa.lat) / (pb.lat - pa.lat) + pa.lng) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Cobertura verde no ponto, de 0 (nenhuma) a 1 (copa densa).
  double canopyAt(GeoPoint p) {
    if (!ready) return 0;
    final i = _i(p.lat), j = _j(p.lng);
    var s = 0.0;
    for (var di = -1; di <= 1; di++) {
      for (var dj = -1; dj <= 1; dj++) {
        final w = (di == 0 && dj == 0) ? 1.0 : 0.4;
        s += (_canopy[_key(i + di, j + dj)] ?? 0) * w;
      }
    }
    return 1 - math.exp(-1.2 * s);
  }

  /// Células com cobertura relevante (para gerar desvios por áreas verdes).
  Iterable<(GeoPoint, double)> greenCells({double minValue = 0.5}) sync* {
    for (final e in _canopy.entries) {
      if (e.value >= minValue) yield (_center(e.key), e.value);
    }
  }

  List<(Oasis, double)> nearestOases(GeoPoint from, {int limit = 15, double maxM = 3000}) {
    final list = <(Oasis, double)>[];
    for (final o in oases) {
      final d = distanceMeters(from, o.point);
      if (d <= maxM) list.add((o, d));
    }
    list.sort((a, b) => a.$2.compareTo(b.$2));
    return list.take(limit).toList();
  }
}
