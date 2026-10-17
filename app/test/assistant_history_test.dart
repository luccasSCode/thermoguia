import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermoguia/core/network/api_client.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/services/location_service.dart';
import 'package:thermoguia/core/storage/local_store.dart';
import 'package:thermoguia/features/assistant/assistant_controller.dart';
import 'package:thermoguia/features/climate/climate_providers.dart';

/// Responde "Resposta N"; com [hold], segura a resposta até liberar.
class _FakeApi extends ApiClient {
  _FakeApi(super.store);
  int n = 0;
  Completer<void>? hold;

  @override
  Future<dynamic> post(String path, [Object? body]) async {
    if (hold != null) await hold!.future;
    return {'reply': 'Resposta ${++n}', 'remainingToday': 10};
  }
}

void main() {
  late SharedPreferences prefs;
  late _FakeApi api;

  ProviderContainer container() => ProviderContainer(overrides: [
        sharedPrefsProvider.overrideWithValue(prefs),
        apiClientProvider.overrideWithValue(api),
        userLocationProvider.overrideWith((_) async => UserLocation.fallback),
      ]);

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    api = _FakeApi(LocalStore(prefs));
  });

  test('fechar guarda a conversa; reabrir continua de onde parou', () async {
    final c = container();
    final ctrl = c.read(assistantProvider.notifier);
    await ctrl.send('Qual o melhor horário para caminhar hoje?');
    expect(c.read(assistantProvider).messages.length, 2);

    ctrl.close();
    final s = c.read(assistantProvider);
    expect(s.isOpen, isFalse);
    expect(s.history.single.title, 'Qual o melhor horário para caminhar hoje?');
    expect(s.history.single.preview, 'Resposta 1');

    ctrl.open(s.history.single.id);
    await ctrl.send('E amanhã?');
    expect(c.read(assistantProvider).messages.map((m) => m.text), [
      'Qual o melhor horário para caminhar hoje?', 'Resposta 1', 'E amanhã?', 'Resposta 2',
    ]);
    expect(c.read(assistantProvider).history.length, 1);
  });

  test('nova conversa guarda a anterior e começa vazia', () async {
    final c = container();
    final ctrl = c.read(assistantProvider.notifier);
    await ctrl.send('Primeira');
    ctrl.newConversation();
    await ctrl.send('Segunda');
    final s = c.read(assistantProvider);
    expect(s.messages.first.text, 'Segunda');
    expect(s.history.map((h) => h.title), ['Segunda', 'Primeira']); // mais recente primeiro
  });

  test('resposta que chega depois de fechar vai para a conversa certa', () async {
    final c = container();
    final ctrl = c.read(assistantProvider.notifier);
    api.hold = Completer();
    final pending = ctrl.send('Vai chover?');
    await Future<void>.delayed(Duration.zero);
    ctrl.close();
    api.hold!.complete();
    await pending;
    final s = c.read(assistantProvider);
    expect(s.isOpen, isFalse);
    expect(s.history.single.messages.map((m) => m.text), ['Vai chover?', 'Resposta 1']);
  });

  test('histórico sobrevive a reabrir o app; apagar uma e apagar todas', () async {
    final c1 = container();
    await c1.read(assistantProvider.notifier).send('A');
    c1.read(assistantProvider.notifier).newConversation();
    await c1.read(assistantProvider.notifier).send('B');
    c1.dispose();

    final c2 = container();
    final ctrl = c2.read(assistantProvider.notifier);
    final history = c2.read(assistantProvider).history;
    expect(history.map((h) => h.title), ['B', 'A']);
    expect(c2.read(assistantProvider).isOpen, isFalse); // abre na tela inicial

    await ctrl.delete(history.last.id);
    expect(c2.read(assistantProvider).history.map((h) => h.title), ['B']);
    await ctrl.clearHistory();
    expect(c2.read(assistantProvider).history, isEmpty);
    c2.dispose();
    expect(container().read(assistantProvider).history, isEmpty);
  });
}
