import 'package:thermo_core/thermo_core.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_store.dart';

class AirData {
  const AirData({required this.current, required this.hourly, required this.fetchedAt, this.stale = false});

  /// Horários já convertidos para o fuso do aparelho.
  final AirPoint current;
  final List<AirPoint> hourly;
  final DateTime fetchedAt;

  /// true quando exibimos dados guardados por falta de conexão.
  final bool stale;

  /// Próximas [hours] horas a partir da hora atual.
  List<AirPoint> next(int hours, {DateTime? now}) {
    final from = now ?? DateTime.now();
    final start = DateTime(from.year, from.month, from.day, from.hour);
    return hourly.where((h) => !h.time.isBefore(start)).take(hours).toList();
  }
}

class AirRepository {
  AirRepository(this._api, this._store);
  final ApiClient _api;
  final LocalStore _store;
  static const _cacheKey = 'air_cache';

  Future<AirData> fetch(GeoPoint at) async {
    try {
      final raw = (await _api.get('/air', query: {'lat': at.lat, 'lng': at.lng}) as Map).cast<String, dynamic>();
      await _store.writeMap(_cacheKey, {...raw, 'fetchedAt': DateTime.now().toIso8601String()});
      return _parse(raw, DateTime.now(), stale: false);
    } on ApiException {
      final cached = _store.readMap(_cacheKey);
      if (cached != null) {
        final at = DateTime.tryParse('${cached['fetchedAt']}') ?? DateTime.now();
        if (DateTime.now().difference(at).inHours < 6) return _parse(cached, at, stale: true);
      }
      rethrow;
    }
  }

  AirData _parse(Map<String, dynamic> raw, DateTime fetchedAt, {required bool stale}) {
    final hourly = (raw['hourly'] as List)
        .map((h) => AirPoint.fromJson((h as Map).cast<String, dynamic>()))
        .map((h) => h.withTime(h.time.toLocal()))
        .toList();
    var current = AirPoint.fromJson((raw['current'] as Map).cast<String, dynamic>());
    if (stale) {
      // Dados guardados: o "agora" é a previsão para a hora atual.
      final now = DateTime.now();
      current = hourly.lastWhere((h) => !h.time.isAfter(now), orElse: () => current);
    }
    return AirData(current: current.withTime(current.time.toLocal()), hourly: hourly, fetchedAt: fetchedAt, stale: stale);
  }
}
