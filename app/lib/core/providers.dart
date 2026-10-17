import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network/api_client.dart';
import 'services/audit_logger.dart';
import 'services/location_service.dart';
import 'services/notification_service.dart';
import 'services/voice_guide.dart';
import 'storage/local_store.dart';

/// Sobrescrito em main() com a instância já carregada.
final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

final localStoreProvider = Provider((ref) => LocalStore(ref.watch(sharedPrefsProvider)));
final apiClientProvider = Provider((ref) => ApiClient(ref.watch(localStoreProvider)));
final locationServiceProvider = Provider((_) => LocationService());
final notificationServiceProvider = Provider((_) => NotificationService());
final auditLoggerProvider = Provider(
  (ref) => AuditLogger(ref.watch(localStoreProvider), ref.watch(apiClientProvider)),
);
final voiceGuideProvider = Provider((_) => VoiceGuide());
