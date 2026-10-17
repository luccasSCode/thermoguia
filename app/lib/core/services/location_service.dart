import 'package:geolocator/geolocator.dart';
import 'package:thermo_core/thermo_core.dart';

import '../config/app_config.dart';

enum LocationStatus { ok, serviceOff, denied, deniedForever }

class UserLocation {
  const UserLocation(this.point, {required this.status});
  final GeoPoint point;
  final LocationStatus status;

  /// Sem GPS: usamos o centro da cidade.
  bool get isApproximate => status != LocationStatus.ok;

  static const fallback = UserLocation(
    GeoPoint(AppConfig.defaultLat, AppConfig.defaultLng),
    status: LocationStatus.denied,
  );
}

class LocationService {
  Future<LocationStatus> ensurePermission({bool request = true}) async {
    if (!await Geolocator.isLocationServiceEnabled()) return LocationStatus.serviceOff;
    var p = await Geolocator.checkPermission();
    if (p == LocationPermission.denied && request) p = await Geolocator.requestPermission();
    return switch (p) {
      LocationPermission.deniedForever => LocationStatus.deniedForever,
      LocationPermission.denied || LocationPermission.unableToDetermine => LocationStatus.denied,
      _ => LocationStatus.ok,
    };
  }

  Future<UserLocation> current() async {
    final status = await ensurePermission();
    if (status != LocationStatus.ok) {
      return UserLocation(UserLocation.fallback.point, status: status);
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return UserLocation(GeoPoint(p.latitude, p.longitude), status: status);
    } catch (_) {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return UserLocation(GeoPoint(last.latitude, last.longitude), status: status);
      return UserLocation(UserLocation.fallback.point, status: LocationStatus.denied);
    }
  }

  Stream<GeoPoint> track() => Geolocator.getPositionStream(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5),
      ).map((p) => GeoPoint(p.latitude, p.longitude));

  Future<void> openSettings() => Geolocator.openAppSettings();
}
