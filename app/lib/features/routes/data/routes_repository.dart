import 'package:thermo_core/thermo_core.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import 'route_models.dart';

class RoutesRepository {
  RoutesRepository(this._api, this._store);
  final ApiClient _api;
  final LocalStore _store;

  Future<List<Place>> search(String q) async {
    final list = await _api.get('/geo/search', query: {'q': q}) as List;
    return list.map((e) => Place.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<RoutesResult> freshRoutes({
    required GeoPoint origin,
    required GeoPoint destination,
    required String mode,
    required DateTime departAt,
    required double shadePreference,
  }) async {
    final data = (await _api.post('/routes/fresh', {
      'origin': origin.toJson(),
      'destination': destination.toJson(),
      'mode': mode,
      'departAt': departAt.toUtc().toIso8601String(),
      'shadePreference': shadePreference,
    }) as Map)
        .cast<String, dynamic>();
    return RoutesResult(
      routes: (data['routes'] as List)
          .map((r) => RouteOption.fromJson((r as Map).cast<String, dynamic>()))
          .toList(),
      advice: data['advice'] as String? ?? '',
      climate: ClimateSnapshot.fromJson((data['climate'] as Map).cast<String, dynamic>()),
      greenReady: data['greenIndexReady'] as bool? ?? false,
    );
  }

  Future<List<Oasis>> oases(GeoPoint at) async {
    final list = await _api.get('/places/oasis', query: {'lat': at.lat, 'lng': at.lng, 'limit': 25}) as List;
    return list.map((e) => Oasis.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  Future<List<CommunityReport>> reports(GeoPoint at) async {
    final list = await _api.get('/reports', query: {'lat': at.lat, 'lng': at.lng}) as List;
    return list.map((e) => CommunityReport.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  /// Devolve a resposta do servidor (com `reward` se rendeu gotas).
  Future<Object?> addReport(ReportKind kind, GeoPoint at, String note) =>
      _api.post('/reports', {'kind': kind.api, 'lat': at.lat, 'lng': at.lng, 'note': note});

  Future<Object?> saveTrip(Map<String, dynamic> trip) => _api.post('/trips', trip);

  // Lugares salvos (Casa, Trabalho...) ficam no aparelho.
  static const _savedKey = 'saved_places';

  List<Place> get savedPlaces =>
      _store.readList(_savedKey).map((e) => Place.fromJson((e as Map).cast<String, dynamic>())).toList();

  Future<void> savePlace(Place p, String label) async {
    final list = savedPlaces.where((x) => x.savedAs != label).toList()
      ..add(Place(name: p.name, address: p.address, lat: p.lat, lng: p.lng, savedAs: label));
    await _store.writeList(_savedKey, list.map((e) => e.toJson()).toList());
  }

  Future<void> removePlace(String label) async => _store.writeList(
        _savedKey,
        savedPlaces.where((x) => x.savedAs != label).map((e) => e.toJson()).toList(),
      );
}
