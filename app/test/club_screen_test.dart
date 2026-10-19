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
      // Próxima conquista: o desconto mais barato que ainda falta liberar.
      expect(find.text('Próxima conquista'), findsOneWidget);
      expect(find.text('5% no fardo de água mineral'), findsOneWidget);
      final list = find.byType(Scrollable).first;
      for (final text in ['Ganhe gotas', 'Descontos', 'Meus cupons', 'Últimas gotas']) {
        await tester.scrollUntilVisible(find.text(text), 250, scrollable: list);
        expect(find.text(text), findsOneWidget);
      }
      // Cupons lado a lado: o número em destaque e o item embaixo.
      await tester.scrollUntilVisible(find.text('Descontos'), -250, scrollable: list);
      final coupons = find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.right);
      await tester.scrollUntilVisible(find.text('Óculos de sol com proteção UV'), 200, scrollable: coupons);
      expect(find.text('25%'), findsOneWidget);
      expect(find.text('ThermoGuia+'), findsWidgets);
      await tester.scrollUntilVisible(find.text('Últimas gotas'), 250, scrollable: list);
      expect(find.textContaining('seguidos abrindo o app = +20 gotas'), findsOneWidget);
    });
  }

  test('destaque do cupom', () {
    expect(couponHeadline('25% em óculos de sol com proteção UV'), '25%');
    expect(couponItem('25% em óculos de sol com proteção UV'), 'Óculos de sol com proteção UV');
    expect(couponHeadline('Leve 3 águas de coco e pague 2'), '3 por 2');
    expect(couponHeadline('Bebida gelada pela metade do preço'), '50%');
  });
}
