import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_mode.dart';
import 'core/widgets/leaf_animation.dart';
import 'features/adaptive/sun_mode.dart';

class ThermoGuiaApp extends ConsumerWidget {
  const ThermoGuiaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sunMode = ref.watch(sunModeActiveProvider);
    final themeMode = ref.watch(themeSettingProvider).mode;
    return MaterialApp.router(
      title: 'ThermoGuia',
      debugShowCheckedModeBanner: false,
      routerConfig: ref.watch(routerProvider),
      theme: AppTheme.build(brightness: Brightness.light, sunMode: sunMode),
      darkTheme: AppTheme.build(brightness: Brightness.dark, sunMode: sunMode),
      // No Modo Sol Forte forçamos o tema claro de alto contraste.
      themeMode: sunMode ? ThemeMode.light : themeMode,
      themeAnimationDuration: const Duration(milliseconds: 350),
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      // A abertura animada fica por fora, para não recomeçar quando o Modo Sol muda.
      builder: (context, child) {
        if (!sunMode) return AnimatedSplash(child: child!);
        // Texto maior no sol, respeitando quem já usa fonte grande.
        final mq = MediaQuery.of(context);
        final scale = (mq.textScaler.scale(16) / 16 * 1.18).clamp(1.18, 1.6);
        return AnimatedSplash(
          child: MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(scale)), child: child!),
        );
      },
    );
  }
}
