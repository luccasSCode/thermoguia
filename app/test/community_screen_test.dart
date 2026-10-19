import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermoguia/core/network/api_client.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/storage/local_store.dart';
import 'package:thermoguia/features/community/community_screen.dart';

// PNG 1×1 transparente.
final _png = base64Decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

class _FakeApi extends ApiClient {
  _FakeApi(super.store);

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async {
    final file = switch (path) {
      '/social/feed' => 'community_feed.json',
      '/social/mine' => 'community_mine.json',
      '/social/badges' => 'community_badges.json',
      _ => null,
    };
    if (file == null) return <dynamic>[];
    return jsonDecode(File('test/$file').readAsStringSync());
  }

  @override
  Future<List<int>> getBytes(String path) async => _png;
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('Comunidade cabe na tela do celular (${dark ? 'escuro' : 'claro'})', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWith((ref) => _FakeApi(LocalStore(prefs))),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const CommunityScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      // O que é o Social e um botão para cada comprovação.
      expect(find.text('O que é o Social'), findsOneWidget);
      expect(find.text('Máscara na fumaça'), findsOneWidget);
      expect(find.text('Print do app aberto'), findsOneWidget);

      // Feed: só posts verificados, com o selo.
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(find.text('Verificado'), findsWidgets);
      expect(find.textContaining('comprovados'), findsWidgets);
      await tester.scrollUntilVisible(find.text('De boné hoje'), 300, scrollable: find.byType(Scrollable).last);

      // Destaques.
      await tester.tap(find.text('Destaques'));
      await tester.pumpAndSettle();
      expect(find.text('Disputa da semana'), findsOneWidget);
      expect(find.textContaining('+ Usou boné'), findsWidgets);

      // Minhas: situação da verificação.
      await tester.tap(find.text('Minhas'));
      await tester.pumpAndSettle();
      expect(find.text('Não comprovado'), findsWidgets);
    });
  }
}
