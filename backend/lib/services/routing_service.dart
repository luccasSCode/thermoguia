import 'dart:convert';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:thermo_core/thermo_core.dart';

import '../config.dart';
import '../http/http_utils.dart';
import 'green_index_service.dart';

class CommunitySignal {
  const CommunitySignal(this.point, this.delta);
  final GeoPoint point;

  /// Positivo = mais sombra relatada; negativo = trecho exposto.
  final double delta;
}

/// Relato da comunidade que vira aviso quando fica no caminho.
class RouteReport {
  const RouteReport(this.kind, this.point, this.note);
  final String kind;
  final GeoPoint point;
  final String note;
}

class FreshRoute {
  FreshRoute({
    required this.points,
    required this.shade,
    required this.distanceM,
    required this.durationS,
    this.maneuvers = const [],
  });

  final List<GeoPoint> points;
  final List<double> shade;
  final double distanceM;
  final double durationS;
  List<Maneuver> maneuvers;
  List<RouteAlert> alerts = const [];

  /// Traçado pela malha de ruas de carro (plano B): parte do caminho pode não
  /// ter calçada ou ciclovia mapeada.
  bool approximate = false;

  double shadeScore = 0;
  double sunExposureMin = 0;
  double thermalLoad = 0;
  double cost = 0;
  String label = 'Alternativa';
  bool recommended = false;
  final tags = <String>[];

  Map<String, dynamic> toJson(int index) => {
        'id': 'r$index',
        'label': label,
        'tags': tags,
        'recommended': recommended,
        'distanceM': distanceM.round(),
        'durationS': durationS.round(),
        'shadeScore': double.parse(shadeScore.toStringAsFixed(3)),
        'sunExposureMin': double.parse(sunExposureMin.toStringAsFixed(1)),
        'thermalLoad': double.parse(thermalLoad.toStringAsFixed(1)),
        'maneuvers': [for (final m in maneuvers) m.toJson()],
        'alerts': [for (final a in alerts) a.toJson()],
        'approximate': approximate,
        'points': [
          for (var i = 0; i < points.length; i++)
            [
              double.parse(points[i].lat.toStringAsFixed(6)),
              double.parse(points[i].lng.toStringAsFixed(6)),
              double.parse(shade[i].toStringAsFixed(2)),
            ],
        ],
      };
}

/// Gera e classifica "Rotas Frescas".
///
/// 1. Pede ao OSRM a rota mais rápida e alternativas.
/// 2. Gera desvios passando por áreas verdes próximas ao trajeto.
/// 3. Pontua cada rota a cada ~20 m: cobertura verde + sombra de prédios
///    conforme a altura do sol no horário de passagem + relatos da comunidade.
/// 4. Ordena pelo custo personalizado (preferência de sombra aprendida).
///    Se o mapa a pé/bicicleta não ligar os pontos (trecho sem calçada mapeada,
///    como o acesso à Ponta Negra), usa a malha de ruas de carro com o tempo
///    recalculado para quem anda ou pedala.
/// 5. Monta as manobras (vire à direita...) e os avisos do caminho: sol forte,
///    lado da rua com sombra, pontos de refresco e relatos da comunidade.
class RoutingService {
  RoutingService(this._config, this._client, this._green);
  final Config _config;
  final http.Client _client;
  final GreenIndexService _green;

  Future<List<FreshRoute>> freshRoutes({
    required GeoPoint origin,
    required GeoPoint destination,
    required String mode,
    required DateTime departAt,
    required ClimateSnapshot climate,
    required double shadePreference,
    List<CommunitySignal> signals = const [],
    List<RouteReport> reports = const [],
  }) async {
    final straight = distanceMeters(origin, destination);
    if (straight < 30) throw ApiError(400, 'Origem e destino estão muito próximos.');
    final maxM = switch (mode) { 'moto' => 40000, 'bike' => 25000, _ => 12000 };
    if (straight > maxM) {
      final what = switch (mode) { 'moto' => 'moto', 'bike' => 'bicicleta', _ => 'caminhada' };
      throw ApiError(400, 'Trajeto longo demais para $what.');
    }

    // Moto (entregador) anda pelas ruas de carro; a sombra continua pesando na escolha.
    var base = switch (mode) {
      'moto' => _config.routingCarUrl,
      'bike' => _config.routingBikeUrl,
      _ => _config.routingFootUrl,
    };
    var routes = await _osrm(base, [origin, destination], alternatives: true);
    final approximate = routes.isEmpty && mode != 'moto';
    if (approximate) {
      base = _config.routingCarUrl;
      routes = await _osrm(base, [origin, destination], alternatives: true);
    }
    if (routes.isEmpty) throw ApiError(404, 'Não encontramos um caminho entre esses pontos.');
    if (approximate) {
      // O tempo do carro não serve: recalcula na velocidade de quem anda ou pedala.
      final speed = mode == 'bike' ? bikeSpeedMs : walkSpeedMs;
      routes = [for (final r in routes) _atSpeed(r, speed)];
    }

    final fastest = routes.map((r) => r.durationS).reduce(math.min);
    // Desvios por áreas verdes só para quem anda ou pedala.
    final limit = switch (mode) { 'moto' => 0, 'bike' => 8000, _ => 6000 };
    if (_green.ready && straight <= limit) {
      for (final via in _greenVias(origin, destination)) {
        try {
          final r = await _osrm(base, [origin, via, destination], alternatives: false);
          if (r.isEmpty) continue;
          final viaRoute = approximate ? _atSpeed(r.first, mode == 'bike' ? bikeSpeedMs : walkSpeedMs) : r.first;
          if (viaRoute.durationS <= fastest * 1.6) routes.add(viaRoute);
        } catch (_) {/* desvio opcional */}
      }
    }

    final unique = <FreshRoute>[];
    for (final r in routes) {
      final dup = unique.any((u) =>
          (u.distanceM - r.distanceM).abs() / u.distanceM < 0.015 &&
          (u.durationS - r.durationS).abs() / u.durationS < 0.015);
      if (!dup) unique.add(r);
    }

    final scored = unique.map((r) => _score(r, departAt, climate, signals)).toList();
    _rank(scored, shadePreference.clamp(0.0, 1.0));
    final top = scored.take(4).toList();
    for (final r in top) {
      _guide(r, departAt, mode, reports);
      r.approximate = approximate;
    }
    return top;
  }

  /// Velocidades médias usadas quando o tempo vem da malha de carro.
  static const walkSpeedMs = 1.3; // ~4,7 km/h
  static const bikeSpeedMs = 4.2; // ~15 km/h

  FreshRoute _atSpeed(FreshRoute r, double speedMs) => FreshRoute(
        points: r.points,
        shade: r.shade,
        distanceM: r.distanceM,
        durationS: r.distanceM / speedMs,
        maneuvers: r.maneuvers,
      );

  /// Rotas do OSRM. Lista vazia quando não há caminho entre os pontos (o OSRM
  /// responde 400 com "NoRoute"); erro 503 só quando o serviço falha de fato.
  Future<List<FreshRoute>> _osrm(String base, List<GeoPoint> pts, {required bool alternatives}) async {
    final coords = pts.map((p) => '${p.lng},${p.lat}').join(';');
    final uri = Uri.parse('$base/route/v1/driving/$coords').replace(queryParameters: {
      'overview': 'full',
      'geometries': 'geojson',
      'alternatives': alternatives ? '3' : 'false',
      'steps': 'true',
    });
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'User-Agent': _config.userAgent})
          .timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ApiError(503, 'Serviço de rotas indisponível no momento.');
    }
    Map<String, dynamic>? data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {}
    if (data?['code'] == 'NoRoute') return [];
    if (res.statusCode != 200 || data == null) throw ApiError(503, 'Serviço de rotas indisponível no momento.');
    if (data['code'] != 'Ok') return [];
    return (data['routes'] as List).cast<Map<String, dynamic>>().map((r) {
      final coords = ((r['geometry'] as Map)['coordinates'] as List)
          .cast<List>()
          .map((c) => GeoPoint((c[1] as num).toDouble(), (c[0] as num).toDouble()))
          .toList();
      return FreshRoute(
        points: coords,
        shade: const [],
        distanceM: (r['distance'] as num).toDouble(),
        durationS: (r['duration'] as num).toDouble(),
        maneuvers: _maneuvers((r['legs'] as List).cast<Map<String, dynamic>>()),
      );
    }).toList();
  }

  /// Manobras de todas as pernas. Nos pontos de passagem (desvio por área
  /// verde) o OSRM gera "chegada" + "partida", que não são manobras reais.
  List<Maneuver> _maneuvers(List<Map<String, dynamic>> legs) {
    final out = <Maneuver>[];
    for (var l = 0; l < legs.length; l++) {
      for (final st in (legs[l]['steps'] as List? ?? const []).cast<Map<String, dynamic>>()) {
        final m = (st['maneuver'] as Map).cast<String, dynamic>();
        final type = m['type'] as String;
        if (type == 'arrive' && l < legs.length - 1) continue;
        if (type == 'depart' && l > 0) continue;
        final loc = (m['location'] as List).cast<num>();
        out.add(Maneuver(
          type: type,
          modifier: m['modifier'] as String? ?? '',
          street: st['name'] as String? ?? '',
          point: GeoPoint(loc[1].toDouble(), loc[0].toDouble()),
          along: 0,
          exit: (m['exit'] as num?)?.toInt(),
        ));
      }
    }
    // "Continue em frente" na mesma rua não ajuda ninguém.
    return [
      for (var i = 0; i < out.length; i++)
        if (!(out[i].type == 'new name' && i > 0 && out[i].street == out[i - 1].street)) out[i],
    ];
  }

  /// Escolhe até 2 pontos de passagem em áreas verdes perto do trajeto direto.
  List<GeoPoint> _greenVias(GeoPoint o, GeoPoint d) {
    final len = distanceMeters(o, d);
    final cosLat = math.cos(o.lat * math.pi / 180);
    // Coordenadas planas locais (metros) para projeção no segmento.
    (double, double) xy(GeoPoint p) =>
        ((p.lng - o.lng) * 111320 * cosLat, (p.lat - o.lat) * 110540);
    final (dx, dy) = xy(d);

    final candidates = <(GeoPoint, double)>[];
    for (final (p, v) in _green.greenCells()) {
      final (px, py) = xy(p);
      final t = (px * dx + py * dy) / (len * len);
      if (t < 0.2 || t > 0.8) continue;
      final perp = ((px * dy - py * dx) / len).abs();
      if (perp < 40 || perp > len * 0.35) continue;
      candidates.add((p, v / (1 + perp / len * 3)));
    }
    candidates.sort((a, b) => b.$2.compareTo(a.$2));

    final picked = <GeoPoint>[];
    for (final (p, _) in candidates) {
      if (picked.every((q) => distanceMeters(p, q) > len * 0.25)) picked.add(p);
      if (picked.length == 2) break;
    }
    return picked;
  }

  FreshRoute _score(FreshRoute r, DateTime when, ClimateSnapshot c, List<CommunitySignal> signals) {
    final pts = _resample(r.points, 20);
    final mid = pts[pts.length ~/ 2];
    final sun = sunPosition(mid.lat, mid.lng, when);

    // Sombra "urbana" (prédios, marquises) depende da altura do sol.
    final urban = !sun.isUp
        ? 1.0
        : sun.elevationDeg < 20
            ? 0.35
            : sun.elevationDeg < 35
                ? 0.15
                : 0.04;

    final shade = <double>[];
    for (final p in pts) {
      final canopy = _green.canopyAt(p);
      var s = canopy + urban * (1 - canopy);
      for (final sig in signals) {
        if (distanceMeters(p, sig.point) < 35) s += sig.delta;
      }
      shade.add(s.clamp(0.0, 1.0));
    }

    final scored = FreshRoute(
      points: pts,
      shade: shade,
      distanceM: r.distanceM,
      durationS: r.durationS,
      maneuvers: r.maneuvers,
    )
      ..shadeScore = shade.reduce((a, b) => a + b) / shade.length;
    final cloudFactor = 1 - 0.6 * (c.cloudCover / 100);
    scored.sunExposureMin =
        sun.isUp ? r.durationS / 60 * (1 - scored.shadeScore) * cloudFactor : 0;
    final hi = heatIndexC(c.temperatureC, c.humidity);
    scored.thermalLoad = scored.sunExposureMin * math.max(0, hi - 26) / 10;
    return scored;
  }

  /// Posiciona as manobras na rota e gera os avisos do caminho.
  void _guide(FreshRoute r, DateTime when, String mode, List<RouteReport> reports) {
    final line = RouteLine(r.points);
    final cum = line.cumulative;
    final foot = mode == 'foot';

    var hint = 0;
    r.maneuvers = [
      for (final m in r.maneuvers)
        (() {
          final fix = line.project(m.point, hint: hint, window: line.points.length);
          hint = fix.segment;
          return Maneuver(
            type: m.type,
            modifier: m.modifier,
            street: m.street,
            point: m.point,
            along: m.type == 'depart' ? 0 : (m.isArrival ? line.length : fix.along),
            exit: m.exit,
          );
        })(),
    ];

    final alerts = <RouteAlert>[];
    final mid = r.points[r.points.length ~/ 2];
    final sun = sunPosition(mid.lat, mid.lng, when);
    final sunny = sun.isUp && sun.elevationDeg > 15;
    final minRun = foot ? 60.0 : 150.0;
    String meters(double m) => m >= 1000
        ? '${(m / 1000).toStringAsFixed(1).replaceAll('.', ',')} km'
        : '${math.max(10, (m / 10).round() * 10)} m';
    double bearingAt(int i) =>
        bearingDeg(r.points[math.min(i, r.points.length - 2)], r.points[math.min(i + 1, r.points.length - 1)]);

    // 1. Sol forte: trechos longos sem sombra.
    if (sunny) {
      for (final (a, b) in runsWhere(line, [for (final v in r.shade) v < 0.3], minM: minRun)) {
        final len = cum[b] - cum[a];
        alerts.add(RouteAlert(
          kind: 'sol_forte',
          message: 'Sol forte nos próximos ${meters(len)}. '
              '${foot ? 'Se puder, use chapéu ou guarda-chuva.' : 'Hidrate-se antes do trecho.'}',
          point: r.points[a],
          along: cum[a],
          length: len,
        ));
      }
    }

    // 2. De que lado da rua estão as árvores (12 m para cada lado).
    final sideRuns = <(int, int)>[];
    if (sunny && foot && _green.ready) {
      final side = <Side?>[];
      for (var i = 0; i < r.points.length; i++) {
        final brg = bearingAt(i);
        final left = _green.canopyAt(offsetPoint(r.points[i], brg - 90, 12));
        final right = _green.canopyAt(offsetPoint(r.points[i], brg + 90, 12));
        side.add(right - left > 0.25 ? Side.direito : (left - right > 0.25 ? Side.esquerdo : null));
      }
      for (final s in Side.values) {
        for (final (a, b) in runsWhere(line, [for (final v in side) v == s], minM: minRun)) {
          sideRuns.add((a, b));
          alerts.add(RouteAlert(
            kind: 'lado_sombra',
            message: 'Árvores do lado ${s.label} nos próximos ${meters(cum[b] - cum[a])}. Prefira esse lado da rua.',
            point: r.points[a],
            along: cum[a],
            length: cum[b] - cum[a],
            side: s,
          ));
        }
      }
      for (final (a, b) in runsWhere(line, [for (final v in r.shade) v >= 0.6], minM: 120)) {
        if (sideRuns.any((x) => x.$1 <= b && a <= x.$2)) continue;
        alerts.add(RouteAlert(
          kind: 'sombra',
          message: 'Trecho arborizado por ${meters(cum[b] - cum[a])}. Bom lugar para uma pausa se precisar.',
          point: r.points[a],
          along: cum[a],
          length: cum[b] - cum[a],
        ));
      }
    }

    // 3. Sombra dos prédios: com o sol baixo, a calçada do lado do sol fica
    //    na sombra das fachadas. Avisamos por rua, onde não há árvores.
    if (foot && sun.isUp && sun.elevationDeg >= 10 && sun.elevationDeg <= 60) {
      for (var k = 0; k < r.maneuvers.length - 1; k++) {
        final m = r.maneuvers[k], next = r.maneuvers[k + 1];
        if (next.along - m.along < 120) continue;
        final a = line.project(line.at(m.along + 5).$1).segment;
        final b = line.project(line.at(next.along - 5).$1).segment;
        if (b <= a || sideRuns.any((x) => x.$1 <= b && a <= x.$2)) continue;
        final exposed = r.shade.sublist(a, b + 1).where((v) => v < 0.55).length / (b - a + 1);
        if (exposed < 0.6) continue;
        final rel = angleDiff(bearingDeg(r.points[a], r.points[b]), sun.azimuthDeg);
        if (rel.abs() < 30 || rel.abs() > 150) continue; // sol na frente ou atrás: sem lado melhor
        final s = rel > 0 ? Side.direito : Side.esquerdo;
        final street = m.street.isEmpty ? 'Neste trecho' : 'Na ${m.street}';
        alerts.add(RouteAlert(
          kind: 'lado_sombra',
          message: '$street, o lado ${s.label} da calçada tem sombra dos prédios.',
          point: m.point,
          along: m.along,
          length: next.along - m.along,
          side: s,
        ));
      }
    }

    // 4. Pontos de refresco colados no caminho.
    if (_green.ready) {
      final near = foot ? 50.0 : 80.0;
      final found = <RouteAlert>[];
      for (final o in _green.oases) {
        if (distanceMeters(o.point, mid) > line.length) continue;
        final fix = line.project(o.point);
        if (fix.offset > near || fix.along > line.length - 30) continue;
        final s = angleDiff(bearingAt(fix.segment), bearingDeg(fix.snapped, o.point)) > 0 ? Side.direito : Side.esquerdo;
        final why = switch (o.kind) {
          'bebedouro' => 'água gratuita',
          'parque' => 'sombra para descansar',
          'farmacia' => 'ar-condicionado e soro',
          _ => 'ar-condicionado',
        };
        found.add(RouteAlert(
          kind: 'refresco',
          message: '${o.name} à ${s == Side.direito ? 'direita' : 'esquerda'}: $why.',
          point: o.point,
          along: fix.along,
          side: s,
        ));
      }
      found.sort((a, b) => a.along.compareTo(b.along));
      var last = -1e9;
      for (final f in found) {
        if (f.along - last < 250) continue;
        alerts.add(f);
        last = f.along;
        if (alerts.where((x) => x.kind == 'refresco').length >= 6) break;
      }
    }

    // 5. Relatos da comunidade em cima da rota.
    for (final rep in reports) {
      final fix = line.project(rep.point);
      if (fix.offset > 30) continue;
      final base = switch (rep.kind) {
        'sem_sombra' => 'Pessoas relataram um trecho sem sombra adiante',
        'calor_extremo' => 'Calor extremo relatado adiante',
        'fumaca' => 'Fumaça forte relatada adiante. Use máscara de proteção',
        'alagamento' => 'Alagamento relatado adiante',
        'transito' => 'Trânsito intenso adiante. Atravesse só na faixa',
        'obra' => 'Obra ou calçada bloqueada adiante',
        'bebedouro' => 'Água disponível adiante',
        'sombra_boa' => 'Boa sombra adiante',
        _ => null,
      };
      if (base == null) continue;
      alerts.add(RouteAlert(
        kind: rep.kind,
        message: rep.note.isEmpty ? '$base.' : '$base: ${rep.note}',
        point: rep.point,
        along: fix.along,
      ));
    }

    alerts.sort((a, b) => a.along.compareTo(b.along));
    r.alerts = alerts;
  }

  void _rank(List<FreshRoute> routes, double w) {
    final minDur = routes.map((r) => r.durationS).reduce(math.min);
    final maxExpo = routes.map((r) => r.sunExposureMin).reduce(math.max);
    for (final r in routes) {
      r.cost = (1 - w) * (r.durationS / minDur) +
          w * (1 - r.shadeScore) * 1.5 +
          w * (r.sunExposureMin / (maxExpo + 1)) * 0.5;
    }
    routes.sort((a, b) => a.cost.compareTo(b.cost));

    final fastest = routes.reduce((a, b) => a.durationS <= b.durationS ? a : b);
    final shadiest = routes.reduce((a, b) => a.shadeScore >= b.shadeScore ? a : b);
    routes.first.recommended = true;
    routes.first.tags.add('Rota Fresca');
    if (!fastest.tags.contains('Mais rápida')) fastest.tags.add('Mais rápida');
    if (routes.length > 1 && !shadiest.tags.contains('Mais sombreada')) {
      shadiest.tags.add('Mais sombreada');
    }
    var n = 1;
    for (final r in routes) {
      r.label = r.tags.isNotEmpty ? r.tags.first : 'Alternativa ${n++}';
    }
  }

  /// Mantém os vértices originais e insere pontos a cada [stepM] metros.
  List<GeoPoint> _resample(List<GeoPoint> pts, double stepM) {
    if (pts.length < 2) return pts;
    final out = <GeoPoint>[pts.first];
    for (var i = 1; i < pts.length; i++) {
      final a = pts[i - 1], b = pts[i];
      final d = distanceMeters(a, b);
      final n = (d / stepM).floor();
      for (var k = 1; k <= n; k++) {
        final t = k * stepM / d;
        if (t < 0.999) out.add(lerpPoint(a, b, t));
      }
      out.add(b);
    }
    return out;
  }
}
