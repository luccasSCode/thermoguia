import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermoguia/core/services/notification_inbox.dart';
import 'package:thermoguia/core/storage/local_store.dart';

void main() {
  test('sino: imediatas entram na hora; programadas, quando o horário passa', () async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final inbox = NotificationInbox(store);
    final now = DateTime(2026, 10, 18, 12);

    await inbox.add(InboxItem(title: 'Fumaça no ar agora', body: '...', at: now, kind: NotifKind.ar));
    expect(inbox.unread, 1);

    await inbox.remember(200, InboxItem(title: 'O ar melhorou', body: '...', at: now.add(const Duration(hours: 2)), kind: NotifKind.ar));
    await inbox.remember(100, InboxItem(title: 'Bom dia!', body: '...', at: now.add(const Duration(hours: 20)), kind: NotifKind.dia));
    await inbox.collectDue(now.add(const Duration(hours: 3)));
    expect(inbox.items.map((i) => i.title), ['O ar melhorou', 'Fumaça no ar agora']);

    // Cancelada antes da hora: não aparece no sino.
    await inbox.forget((id) => id >= 100 && id <= 199);
    await inbox.collectDue(now.add(const Duration(days: 2)));
    expect(inbox.items, hasLength(2));

    await inbox.markAllRead();
    expect(inbox.unread, 0);
    // Continua salvo depois de reabrir o app.
    expect(NotificationInbox(store).items, hasLength(2));
  });
}
