import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:thermoguia/core/providers.dart';
import 'package:thermoguia/core/widgets/leaf_animation.dart';
import 'package:thermoguia/features/session/presentation/onboarding_screen.dart';
import 'package:thermoguia/features/session/presentation/persona_picker.dart';
import 'package:thermoguia/features/session/presentation/social_sign_in.dart';
import 'package:thermoguia/features/session/presentation/welcome_screen.dart';

void main() {
  for (final dark in [false, true]) {
    testWidgets('boas-vindas e perfil cabem na tela sem rolar (${dark ? 'escuro' : 'claro'})', (tester) async {
      tester.view.physicalSize = const Size(360 * 3, 800 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final router = GoRouter(initialLocation: '/boas-vindas', routes: [
        GoRoute(path: '/boas-vindas', builder: (_, __) => const WelcomeScreen()),
        GoRoute(path: '/comecar', builder: (_, __) => const OnboardingScreen()),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
          theme: ThemeData(brightness: dark ? Brightness.dark : Brightness.light),
          routerConfig: router,
        ),
      ));
      await tester.pump(const Duration(seconds: 6));

      double scrollExtent() =>
          tester.state<ScrollableState>(find.byType(Scrollable).first).position.maxScrollExtent;

      expect(scrollExtent(), 0);
      for (final p in SocialProvider.values) {
        expect(find.text(p.label), findsOneWidget);
      }
      expect(find.byType(SocialLogo), findsNWidgets(2));

      // Os botões sociais só levam à escolha de perfil.
      await tester.tap(find.text('Entrar com o Facebook'));
      await tester.pumpAndSettle();
      expect(find.text('Como você costuma andar pela cidade?'), findsOneWidget);
      expect(scrollExtent(), 0);

      // O perfil com o texto mais longo também cabe.
      await tester.tap(find.text('Idoso'));
      await tester.pumpAndSettle();
      expect(scrollExtent(), 0);
      expect(find.text('Continuar'), findsOneWidget);
    });
  }

  testWidgets('cada perfil explica o que muda antes do cadastro', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    var persona = Persona.pedestre;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SingleChildScrollView(
            child: PersonaPicker(value: persona, showBenefits: true, onChanged: (p) => setState(() => persona = p)),
          ),
        ),
      ),
    ));
    for (final p in Persona.values) {
      await tester.tap(find.text(personaShortLabel(p)));
      await tester.pumpAndSettle();
      expect(find.text('O que muda para ${personaShortLabel(p).toLowerCase()}:'), findsOneWidget);
      // Resumido: três diferenciais curtos por perfil.
      expect(personaBenefits(p), hasLength(3));
    }
    expect(find.textContaining('respira 2× mais'), findsNothing);
    await tester.tap(find.text('Ciclista'));
    await tester.pumpAndSettle();
    expect(find.textContaining('respira 2× mais'), findsOneWidget);
  });

  testWidgets('a abertura animada some sozinha e deixa o app à mostra', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: AnimatedSplash(child: Text('Tela do app'))));
    expect(find.byType(LeafAnimation), findsOneWidget);
    await tester.pump(const Duration(seconds: 5)); // a folha termina de brotar
    await tester.pump(const Duration(milliseconds: 300)); // pausa antes de sumir
    await tester.pumpAndSettle();
    expect(find.byType(LeafAnimation), findsNothing);
    expect(find.text('Tela do app'), findsOneWidget);
  });
}
