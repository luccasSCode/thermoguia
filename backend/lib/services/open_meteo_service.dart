import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:thermo_core/thermo_core.dart';

import '../http/http_utils.dart';

class ClimateBundle {
  ClimateBundle(this.current, this.hourly);
  final ClimateSnapshot current;
  final List<HourlyPoint> hourly;

  /// Condições previstas para um instante (usa a hora mais próxima).
  ClimateSnapshot at(DateTime when) {
    if (hourly.isEmpty || when.difference(current.time).inMinutes.abs() < 45) {
      return current;
    }
    final h = hourly.reduce((a, b) =>
        a.time.difference(when).abs() < b.time.difference(when).abs() ? a : b);
    return ClimateSnapshot(
      time: when,
      temperatureC: h.temperatureC,
      humidity: h.humidity,
      apparentC: heatIndexC(h.temperatureC, h.humidity),
      uvIndex: h.uvIndex,
      windKmh: current.windKmh,
      precipitationProb: h.precipitationProb,
      cloudCover: current.cloudCover,
      isDay: h.uvIndex > 0.2,
    );
  }

  Map<String, dynamic> toJson() => {
        'current': current.toJson(),
        'hourly': hourly.map((h) => h.toJson()).toList(),
      };
}

/// Dados meteorológicos do Open-Meteo (gratuito, sem chave de API).
/// Cache de 10 minutos por célula de ~2 km.
class OpenMeteoService {
  OpenMeteoService(this._client);
  final http.Client _client;
  final _cache = <String, (DateTime, ClimateBundle)>{};

  Future<ClimateBundle> fetch(double lat, double lng) async {
    final key = '${(lat * 50).round()}:${(lng * 50).round()}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1).inMinutes < 10) {
      return hit.$2;
    }

    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': lat.toStringAsFixed(4),
      'longitude': lng.toStringAsFixed(4),
      'current': 'temperature_2m,relative_humidity_2m,apparent_temperature,'
          'is_day,cloud_cover,wind_speed_10m',
      'hourly': 'temperature_2m,relative_humidity_2m,uv_index,precipitation_probability,precipitation,weather_code',
      'timezone': 'GMT',
      'forecast_days': '2',
    });

    final http.Response res;
    try {
      res = await _client.get(uri).timeout(const Duration(seconds: 12));
    } catch (_) {
      if (hit != null) return hit.$2;
      throw ApiError(503, 'Serviço de clima indisponível no momento.');
    }
    if (res.statusCode != 200) {
      if (hit != null) return hit.$2;
      throw ApiError(503, 'Serviço de clima indisponível no momento.');
    }

    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final bundle = _parse(data);
    _cache[key] = (DateTime.now(), bundle);
    if (_cache.length > 500) _cache.remove(_cache.keys.first);
    return bundle;
  }

  ClimateBundle _parse(Map<String, dynamic> data) {
    DateTime utc(String s) => DateTime.parse(s.endsWith('Z') ? s : '${s}Z');
    double n(Object? v) => v is num ? v.toDouble() : 0;

    final h = data['hourly'] as Map<String, dynamic>;
    final times = (h['time'] as List).cast<String>();
    final hourly = <HourlyPoint>[
      for (var i = 0; i < times.length; i++)
        HourlyPoint(
          time: utc(times[i]),
          temperatureC: n((h['temperature_2m'] as List)[i]),
          humidity: n((h['relative_humidity_2m'] as List)[i]),
          uvIndex: n((h['uv_index'] as List)[i]),
          precipitationProb: n((h['precipitation_probability'] as List)[i]),
          precipitationMm: n((h['precipitation'] as List?)?[i]),
          weatherCode: ((h['weather_code'] as List?)?[i] as num?)?.toInt(),
        ),
    ];

    final c = data['current'] as Map<String, dynamic>;
    final now = utc(c['time'] as String);
    final thisHour = hourly.lastWhere(
      (p) => !p.time.isAfter(now),
      orElse: () => hourly.first,
    );

    final current = ClimateSnapshot(
      time: now,
      temperatureC: n(c['temperature_2m']),
      humidity: n(c['relative_humidity_2m']),
      apparentC: n(c['apparent_temperature']),
      uvIndex: thisHour.uvIndex,
      windKmh: n(c['wind_speed_10m']),
      precipitationProb: thisHour.precipitationProb,
      cloudCover: n(c['cloud_cover']),
      isDay: c['is_day'] == 1,
    );
    return ClimateBundle(current, hourly);
  }
}
