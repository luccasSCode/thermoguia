import '../network/api_client.dart';
import '../storage/local_store.dart';

class AuditEntry {
  AuditEntry({
    required this.action,
    required this.at,
    this.approved,
    this.details = const {},
    this.synced = false,
  });

  final String action;
  final DateTime at;
  final bool? approved;
  final Map<String, dynamic> details;
  bool synced;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        action: j['action'] as String,
        at: DateTime.parse((j['at'] ?? j['created_at']) as String).toLocal(),
        approved: j['approved'] as bool?,
        details: (j['details'] as Map?)?.cast<String, dynamic>() ?? const {},
        synced: j['synced'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'action': action,
        'at': at.toUtc().toIso8601String(),
        'approved': approved,
        'details': details,
        'synced': synced,
      };
}

/// Registra decisões do agente e do usuário. Grava localmente primeiro
/// (funciona offline) e sincroniza com o servidor quando possível.
class AuditLogger {
  AuditLogger(this._store, this._api);
  final LocalStore _store;
  final ApiClient _api;
  static const _key = 'audit_log';

  List<AuditEntry> get local => _store
      .readList(_key)
      .map((e) => AuditEntry.fromJson((e as Map).cast<String, dynamic>()))
      .toList();

  Future<void> log(String action, {bool? approved, Map<String, dynamic> details = const {}}) async {
    final entry = AuditEntry(action: action, at: DateTime.now(), approved: approved, details: details);
    final list = [entry, ...local];
    await _save(list);
    await _send(entry);
    await _save(list);
  }

  /// Reenvia registros que ficaram pendentes por falta de conexão.
  Future<void> flush() async {
    final list = local;
    for (final e in list.where((e) => !e.synced)) {
      await _send(e);
    }
    await _save(list);
  }

  Future<void> _send(AuditEntry e) async {
    try {
      await _api.post('/audit', {
        'action': e.action,
        'approved': e.approved,
        'details': {...e.details, 'clientAt': e.at.toUtc().toIso8601String()},
      });
      e.synced = true;
    } catch (_) {}
  }

  Future<void> _save(List<AuditEntry> list) =>
      _store.writeList(_key, list.take(300).map((e) => e.toJson()).toList());
}
