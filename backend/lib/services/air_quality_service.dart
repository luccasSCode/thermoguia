import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:thermo_core/thermo_core.dart';

import '../http/http_utils.dart';

class AirBundle {
  AirBundle(this.current, this.hourly);
  final AirPoint current;
  final List<AirPoint> hourly;

  Map<String, dynamic> toJson() => {
        'current': current.toJson(),
        'hourly': hourly.map((h) => h.toJson()).toList(),
      };
}

/// Qualidade do ar do Open-Meteo (modelo CAMS, que inclui a fumaça das
/// queimadas). Gratuito e sem chave. Cache de 20 minutos por célula de ~2 km.
class AirQualityService {
  AirQualityService(this._client);
  final http.Client _client;
  final _cache = <String, (DateTime, AirBundle)>{};

  Future<AirBundle> fetch(double lat, double lng) async {
    final key = '${(lat * 50).round()}:${(lng * 50).round()}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 20) {
      return hit.$2;
    }

    final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lng.toStringAsFixed(4),
      'current': 'pm10,pm2_5',
      'hourly': 'pm10,pm2_5',
      'timezone': 'GMT',
      'forecast_days': '3',
    });

    final http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 12));
    } catch (_) {
      if (hit != null) return hit.$2;
      throw ApiError(503, 'Serviço de qualidade do ar indisponível no momento.');
    }
    if (res.statusCode != 200) {
      if (hit != null) return hit.$2;
      throw ApiError(503, 'Serviço de qualidade do ar indisponível no momento.');
    }

    final bundle = _parse(jsonDecode(res.body) as Map<String, dynamic>);
    _cache[key] = (DateTime.now(), bundle);
    if (_cache.length > 500) _cache.remove(_cache.keys.first);
    return bundle;
  }

  final _grids = <String, (DateTime, List<Map<String, dynamic>>)>{};

  /// Fumaça agora numa grade de [n]×[n] pontos sobre a cidade, para pintar o mapa.
  /// O modelo tem resolução de dezenas de km: as diferenças entre bairros são
  /// suaves, e os relatos de fumaça da comunidade completam o retrato.
  Future<List<Map<String, dynamic>>> grid(GeoBounds b, {int n = 5}) async {
    final key = '${b.south}:${b.west}:$n';
    final hit = _grids[key];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 30) return hit.$2;

    final lats = <double>[], lngs = <double>[];
    for (var i = 0; i < n; i++) {
      for (var j = 0; j < n; j++) {
        lats.add(b.south + (b.north - b.south) * (i + 0.5) / n);
        lngs.add(b.west + (b.east - b.west) * (j + 0.5) / n);
      }
    }
    final uri = Uri.https('air-quality-api.open-meteo.com', '/v1/air-quality', {
      'latitude': lats.map((v) => v.toStringAsFixed(4)).join(','),
      'longitude': lngs.map((v) => v.toStringAsFixed(4)).join(','),
      'current': 'pm10,pm2_5',
      'timezone': 'GMT',
    });
    http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 15));
    } catch (_) {
      if (hit != null) return hit.$2;
      throw ApiError(503, 'Mapa de fumaça indisponível no momento.');
    }
    if (res.statusCode != 200) {
      if (hit != null) return hit.$2;
      throw ApiError(503, 'Mapa de fumaça indisponível no momento.');
    }
    final body = jsonDecode(res.body);
    final list = body is List ? body : [body];
    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < list.length && i < lats.length; i++) {
      final c = (list[i] as Map)['current'];
      if (c is! Map || c['pm2_5'] is! num) continue;
      final p = AirPoint(time: DateTime.now().toUtc(), pm25: (c['pm2_5'] as num).toDouble(), pm10: (c['pm10'] as num? ?? 0).toDouble());
      out.add({'lat': lats[i], 'lng': lngs[i], 'pm25': p.pm25, 'pm10': p.pm10, 'index': p.index, 'level': p.level.name});
    }
    _grids[key] = (DateTime.now(), out);
    return out;
  }

  AirBundle _parse(Map<String, dynamic> data) {
    DateTime utc(String s) => DateTime.parse(s.endsWith('Z') ? s : '${s}Z');
    double n(Object? v) => v is num ? v.toDouble() : 0;

    final h = data['hourly'] as Map<String, dynamic>;
    final times = (h['time'] as List).cast<String>();
    final pm25 = h['pm2_5'] as List;
    final pm10 = h['pm10'] as List;
    final hourly = <AirPoint>[
      for (var i = 0; i < times.length; i++)
        // Horas sem previsão vêm como null: melhor pular do que fingir ar limpo.
        if (pm25[i] != null) AirPoint(time: utc(times[i]), pm25: n(pm25[i]), pm10: n(pm10[i])),
    ];

    final c = data['current'] as Map<String, dynamic>?;
    final current = c != null && c['pm2_5'] != null
        ? AirPoint(time: utc(c['time'] as String), pm25: n(c['pm2_5']), pm10: n(c['pm10']))
        : hourly.lastWhere((p) => !p.time.isAfter(DateTime.now().toUtc()), orElse: () => hourly.first);
    return AirBundle(current, hourly);
  }
}
