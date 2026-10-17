import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermoguia/core/network/api_client.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/storage/local_store.dart';
import 'package:thermoguia/features/rewards/club_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi(super.store);

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      jsonDecode(File('test/rewards_fixture.json').readAsStringSync());
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('Clube H2O cabe na tela do celular (${dark ? 'escuro' : 'claro'})', (tester) async {
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
          home: const ClubScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('gotas'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      for (final text in ['Meus cupons', 'Troque suas gotas', '25% em óculos de sol com proteção UV', 'Como ganhar gotas', 'Últimas gotas']) {
        await tester.scrollUntilVisible(find.text(text), 250, scrollable: list);
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('ThermoGuia+'), findsWidgets);
      expect(find.text('Exemplo'), findsWidgets);
    });
  }
}
