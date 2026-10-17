import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermoguia/core/network/api_client.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/storage/local_store.dart';
import 'package:thermoguia/features/profile/avatar.dart';
import 'package:thermoguia/features/session/presentation/session_controller.dart';

Map<String, dynamic> _user(String? version) => {
      'id': 'u1', 'name': 'Ana', 'persona': 'pedestre', 'plan': 'free', 'isAnonymous': true,
      'avatarUpdatedAt': version,
    };

class _FakeApi extends ApiClient {
  _FakeApi(super.store, this.version);
  String? version;
  int downloads = 0;

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async => _user(version);

  @override
  Future<List<int>> getBytes(String path) async {
    downloads++;
    return [0xFF, 0xD8, 0xFF, downloads];
  }
}

void main() {
  test('baixa a foto uma vez, usa o cache e troca quando a versão muda', () async {
    SharedPreferences.setMockInitialValues({'auth_token': 't', 'cached_user': jsonEncode(_user('v1'))});
    final prefs = await SharedPreferences.getInstance();
    final api = _FakeApi(LocalStore(prefs), 'v1');
    ProviderContainer make() => ProviderContainer(overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWithValue(api),
        ]);

    var c = make();
    c.read(sessionProvider);
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(avatarProvider.future), [0xFF, 0xD8, 0xFF, 1]);
    expect(api.downloads, 1);
    c.dispose();

    // App reaberto: vem do cache, sem baixar de novo.
    c = make();
    c.read(sessionProvider);
    await Future<void>.delayed(Duration.zero);
    expect(await c.read(avatarProvider.future), [0xFF, 0xD8, 0xFF, 1]);
    expect(api.downloads, 1);
    c.dispose();

    // Foto trocada em outro aparelho: versão nova, baixa e apaga a antiga.
    api.version = 'v2';
    c = make();
    c.read(sessionProvider);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(await c.read(avatarProvider.future), [0xFF, 0xD8, 0xFF, 2]);
    expect(prefs.getKeys().where((k) => k.startsWith('avatar_')), ['avatar_v2']);

    // Sem foto: nada a mostrar.
    api.version = null;
    await c.read(sessionProvider).restore();
    expect(await c.read(avatarProvider.future), isNull);
    c.dispose();
  });
}
