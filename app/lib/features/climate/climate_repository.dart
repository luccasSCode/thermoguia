import 'package:thermo_core/thermo_core.dart';

import '../../core/network/api_client.dart';
import '../../core/storage/local_store.dart';

class ClimateData {
  const ClimateData({required this.current, required this.hourly, required this.fetchedAt, this.stale = false});

  /// Horários já convertidos para o fuso do aparelho.
  final ClimateSnapshot current;
  final List<HourlyPoint> hourly;
  final DateTime fetchedAt;

  /// true quando exibimos dados guardados por falta de conexão.
  final bool stale;
}

class ClimateRepository {
  ClimateRepository(this._api, this._store);
  final ApiClient _api;
  final LocalStore _store;
  static const _cacheKey = 'climate_cache';

  Future<ClimateData> fetch(GeoPoint at) async {
    try {
      final raw = (await _api.get('/climate', query: {'lat': at.lat, 'lng': at.lng}) as Map)
          .cast<String, dynamic>();
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

  ClimateData _parse(Map<String, dynamic> raw, DateTime fetchedAt, {required bool stale}) {
    final current = ClimateSnapshot.fromJson((raw['current'] as Map).cast<String, dynamic>());
    final hourly = (raw['hourly'] as List)
        .map((h) => HourlyPoint.fromJson((h as Map).cast<String, dynamic>()))
        .map((h) => h.withTime(h.time.toLocal()))
        .toList();
    // Para dados guardados, o "agora" é o horário atual, não o da coleta.
    final now = stale ? DateTime.now() : current.time.toLocal();
    return ClimateData(current: current.withTime(now), hourly: hourly, fetchedAt: fetchedAt, stale: stale);
  }
}
