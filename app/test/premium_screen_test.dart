import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermoguia/core/network/api_client.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/storage/local_store.dart';
import 'package:thermoguia/features/profile/premium_screen.dart';

class _FakeApi extends ApiClient {
  _FakeApi(super.store);

  @override
  Future<dynamic> get(String path, {Map<String, dynamic>? query}) async =>
      jsonDecode(File('test/plans_fixture.json').readAsStringSync());
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('planos cabem na tela do celular (${dark ? 'escuro' : 'claro'})', (tester) async {
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
          home: const PremiumScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Anual'));
      await tester.pumpAndSettle();
      expect(find.text('R\$ 79,90/ano'), findsOneWidget);

      // Rola a tela inteira; qualquer estouro de layout falha o teste.
      final list = find.byType(Scrollable).first;
      for (final text in [
        'Grátis × ThermoGuia+',
        'Sincronizar com smartwatch',
        '1 relógio: alertas de risco e lembretes de água',
        'Falar com a equipe',
      ]) {
        await tester.scrollUntilVisible(find.text(text), 250, scrollable: list);
        expect(find.text(text), findsOneWidget);
      }
    });
  }
}
