import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermoguia/core/network/api_client.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/storage/local_store.dart';
import 'package:thermoguia/features/profile/donate_screen.dart';

class _OfflineApi extends ApiClient {
  _OfflineApi(super.store);

  @override
  Future<dynamic> post(String path, [Object? body]) async => throw ApiException('Sem conexão.');
}

void main() {
  for (final dark in [false, true]) {
    testWidgets('doação cabe na tela e mostra o impacto do valor (${dark ? 'escuro' : 'claro'})', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          apiClientProvider.overrideWith((ref) => _OfflineApi(LocalStore(prefs))),
        ],
        child: MaterialApp(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          home: const DonateScreen(),
        ),
      ));
      await tester.pumpAndSettle();

      final list = find.byType(Scrollable).first;
      // Começa em R$ 50: plantar 3 árvores.
      await tester.scrollUntilVisible(find.text('Doar R\$ 50'), 250, scrollable: list);
      expect(find.textContaining('Com R\$ 50 você ajuda a plantar 3 árvores'), findsOneWidget);
      expect(find.text('Doar R\$ 50'), findsOneWidget);

      await tester.scrollUntilVisible(find.text('R\$ 25'), -250, scrollable: list);
      await tester.tap(find.text('R\$ 25'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Doar R\$ 25'), 250, scrollable: list);
      expect(find.textContaining('Com R\$ 25 você ajuda a entregar máscaras'), findsOneWidget);
      expect(find.textContaining('menos gente respirando fumaça'), findsWidgets);

      // Rola a tela inteira; qualquer estouro de layout falha o teste.
      await tester.scrollUntilVisible(find.textContaining('Doação voluntária'), 250, scrollable: list);
      expect(find.text('Para onde vai a sua doação'), findsOneWidget);

      // Sem chave Pix na compilação, o botão só agradece e registra o interesse.
      await tester.scrollUntilVisible(find.text('Doar R\$ 25'), -250, scrollable: list);
      await tester.tap(find.text('Doar R\$ 25'));
      await tester.pump();
      expect(find.textContaining('Obrigado!'), findsOneWidget);
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
