import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../../core/services/audit_logger.dart';

class EmergencyContact {
  const EmergencyContact(this.id, this.name, this.phone, this.relation);
  final String id;
  final String name;
  final String phone;
  final String relation;

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
        j['id'] as String,
        j['name'] as String,
        j['phone'] as String,
        j['relation'] as String? ?? '',
      );
}

class SafetyRepository {
  SafetyRepository(this._api, this._audit);
  final ApiClient _api;
  final AuditLogger _audit;

  Future<List<EmergencyContact>> contacts() async => (await _api.get('/emergency/contacts') as List)
      .map((e) => EmergencyContact.fromJson((e as Map).cast<String, dynamic>()))
      .toList();

  Future<void> addContact(String name, String phone, String relation) =>
      _api.post('/emergency/contacts', {'name': name, 'phone': phone, 'relation': relation});

  Future<void> removeContact(String id) => _api.delete('/emergency/contacts/$id');

  /// Registra a decisão no servidor. Sem conexão, guarda no log local
  /// para sincronizar depois.
  Future<Map<String, dynamic>> logEvent({
    required String action,
    required bool approved,
    required List<String> symptoms,
    required String trigger,
    String? riskLevel,
    List<String> contactIds = const [],
    double? lat,
    double? lng,
  }) async {
    try {
      return (await _api.post('/emergency/events', {
        'action': action,
        'approved': approved,
        'symptoms': symptoms,
        'trigger': trigger,
        'riskLevel': riskLevel,
        'contactIds': contactIds,
        'lat': lat,
        'lng': lng,
      }) as Map)
          .cast<String, dynamic>();
    } on ApiException catch (e) {
      if (!e.isOffline) rethrow;
      await _audit.log('emergencia_$action', approved: approved, details: {
        'symptoms': symptoms,
        'trigger': trigger,
        'offline': true,
      });
      if (approved && action == 'share_location' && lat != null && lng != null) {
        final maps = 'https://maps.google.com/?q=$lat,$lng';
        return {'message': 'Preciso de ajuda, posso estar passando mal por causa do calor. Estou aqui: $maps'};
      }
      return const {};
    }
  }

  Future<List<AuditEntry>> history() async {
    try {
      final list = await _api.get('/audit', query: {'limit': 100}) as List;
      return list.map((e) => AuditEntry.fromJson((e as Map).cast<String, dynamic>())).toList();
    } on ApiException {
      return _audit.local;
    }
  }
}

final safetyRepositoryProvider = Provider(
  (ref) => SafetyRepository(ref.watch(apiClientProvider), ref.watch(auditLoggerProvider)),
);

final contactsProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(safetyRepositoryProvider).contacts(),
);
