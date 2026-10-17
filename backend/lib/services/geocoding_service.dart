import 'dart:convert';

import 'package:http/http.dart' as http;

import '../cities.dart';
import '../config.dart';
import '../http/http_utils.dart';

/// Busca de endereços restrita à cidade (Nominatim / OpenStreetMap).
class GeocodingService {
  GeocodingService(this._config, this._client);
  final Config _config;
  final http.Client _client;
  final _cache = <String, (DateTime, List<Map<String, dynamic>>)>{};

  Future<List<Map<String, dynamic>>> search(String q, City city) async {
    final key = '${city.id}:${q.toLowerCase().trim()}';
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.$1).inHours < 24) return hit.$2;

    final b = city.bounds;
    final uri = Uri.parse('${_config.nominatimUrl}/search').replace(queryParameters: {
      'q': q,
      'format': 'jsonv2',
      'limit': '8',
      'countrycodes': 'br',
      'viewbox': '${b.west},${b.north},${b.east},${b.south}',
      'bounded': '1',
      'accept-language': 'pt-BR',
    });
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'User-Agent': _config.userAgent})
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      throw ApiError(503, 'Busca de endereços indisponível no momento.');
    }
    if (res.statusCode != 200) throw ApiError(503, 'Busca de endereços indisponível no momento.');

    final list = (jsonDecode(utf8.decode(res.bodyBytes)) as List).cast<Map<String, dynamic>>();
    final results = list.map((e) {
      final display = e['display_name'] as String? ?? '';
      final name = (e['name'] as String?)?.trim();
      return {
        'name': (name == null || name.isEmpty) ? display.split(',').first : name,
        'address': display.split(',').skip(1).take(3).join(',').trim(),
        'lat': double.parse('${e['lat']}'),
        'lng': double.parse('${e['lon']}'),
      };
    }).toList();
    _cache[key] = (DateTime.now(), results);
    return results;
  }
}
