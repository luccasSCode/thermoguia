import 'package:flutter/foundation.dart';

import '../storage/local_store.dart';

/// Tipos de notificação, cada um pode ser ligado ou desligado em Configurações.
enum NotifKind {
  agua('Lembretes de água', 'Durante "Estou na rua agora", no ritmo do calor'),
  calor('Alertas de calor', 'Quando o calor fica extremo onde você está'),
  ar('Fumaça e qualidade do ar', 'Quando usar máscara, fechar as janelas e quando o ar fica bom'),
  tempo('Chuva, temporal e sol', 'Com antecedência: risco de alagamento, temporal, chuva forte, calor extremo e sol forte'),
  dia('Resumo do dia e Clube H2O', 'Resumo da manhã, pico de calor, fim de tarde e sua sequência');

  const NotifKind(this.title, this.subtitle);
  final String title;
  final String subtitle;

  static NotifKind fromName(String? n) => values.firstWhere((k) => k.name == n, orElse: () => dia);
}

class InboxItem {
  const InboxItem({required this.title, required this.body, required this.at, required this.kind, this.route, this.read = false});
  final String title;
  final String body;
  final DateTime at;
  final NotifKind kind;
  final String? route;
  final bool read;

  InboxItem copyWith({bool? read}) =>
      InboxItem(title: title, body: body, at: at, kind: kind, route: route, read: read ?? this.read);

  factory InboxItem.fromJson(Map<String, dynamic> j) => InboxItem(
        title: '${j['title']}',
        body: '${j['body']}',
        at: DateTime.tryParse('${j['at']}') ?? DateTime.now(),
        kind: NotifKind.fromName(j['kind'] as String?),
        route: j['route'] as String?,
        read: j['read'] == true,
      );

  Map<String, dynamic> toJson() =>
      {'title': title, 'body': body, 'at': at.toIso8601String(), 'kind': kind.name, 'route': route, 'read': read};
}

/// Tudo o que o app mostrou como notificação, para o sino da tela Agora.
///
/// As imediatas entram na hora. As programadas ficam anotadas e entram na
/// caixa quando o horário delas passa (o sistema entrega com o app fechado,
/// então conferimos ao abrir).
class NotificationInbox extends ChangeNotifier {
  NotificationInbox(this._store) {
    _items = _store.readList(_key).map((e) => InboxItem.fromJson((e as Map).cast<String, dynamic>())).toList();
  }

  final LocalStore _store;
  static const _key = 'notif_inbox';
  static const _scheduledKey = 'notif_scheduled';
  static const _max = 60;
  late List<InboxItem> _items;

  List<InboxItem> get items => List.unmodifiable(_items);
  int get unread => _items.where((i) => !i.read).length;

  Future<void> add(InboxItem item) async {
    _items = [item, ..._items].take(_max).toList();
    await _save();
  }

  Future<void> markAllRead() async {
    if (unread == 0) return;
    _items = [for (final i in _items) i.copyWith(read: true)];
    await _save();
  }

  Future<void> clear() async {
    _items = [];
    await _save();
  }

  /// Guarda uma notificação programada para entrar na caixa quando chegar a hora.
  Future<void> remember(int id, InboxItem item) async {
    final m = _store.readMap(_scheduledKey) ?? {};
    m['$id'] = item.toJson();
    await _store.writeMap(_scheduledKey, m);
  }

  Future<void> forget(bool Function(int id) test) async {
    final m = _store.readMap(_scheduledKey) ?? {};
    m.removeWhere((k, _) => test(int.tryParse(k) ?? -1));
    await _store.writeMap(_scheduledKey, m);
  }

  /// Move para a caixa as programadas cujo horário já passou.
  Future<void> collectDue([DateTime? now]) async {
    final at = now ?? DateTime.now();
    final m = _store.readMap(_scheduledKey) ?? {};
    final due = <InboxItem>[];
    m.removeWhere((_, v) {
      final item = InboxItem.fromJson((v as Map).cast<String, dynamic>());
      if (item.at.isAfter(at)) return false;
      due.add(item);
      return true;
    });
    if (due.isEmpty) return;
    due.sort((a, b) => b.at.compareTo(a.at));
    _items = [...due, ..._items].take(_max).toList();
    await _store.writeMap(_scheduledKey, m);
    await _save();
  }

  Future<void> _save() async {
    await _store.writeList(_key, _items.map((i) => i.toJson()).toList());
    notifyListeners();
  }
}
