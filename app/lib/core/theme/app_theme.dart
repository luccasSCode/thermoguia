import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'tokens.dart';

/// Marca o tema como "Modo Sol Forte" para widgets que desenham à mão.
class ThermoVisuals extends ThemeExtension<ThermoVisuals> {
  const ThermoVisuals({required this.sunMode});
  final bool sunMode;

  @override
  ThermoVisuals copyWith({bool? sunMode}) => ThermoVisuals(sunMode: sunMode ?? this.sunMode);

  @override
  ThermoVisuals lerp(ThermoVisuals? other, double t) => t < 0.5 ? this : (other ?? this);
}

extension ThermoThemeX on BuildContext {
  bool get sunMode => Theme.of(this).extension<ThermoVisuals>()?.sunMode ?? false;
}

abstract final class AppTheme {
  static ThemeData build({required Brightness brightness, required bool sunMode}) {
    final dark = brightness == Brightness.dark && !sunMode;

    final scheme = sunMode
        ? const ColorScheme.light(
            primary: Color(0xFF0A3D6B),
            onPrimary: Colors.white,
            secondary: Color(0xFF9A4A00),
            onSecondary: Colors.white,
            tertiary: Color(0xFF145C3B),
            surface: Colors.white,
            onSurface: Colors.black,
            surfaceContainerHighest: Color(0xFFF2F2F2),
            outline: Colors.black,
            error: Color(0xFF9B0000),
          )
        : ColorScheme.fromSeed(
            seedColor: Tokens.rio,
            brightness: dark ? Brightness.dark : Brightness.light,
          ).copyWith(
            primary: dark ? const Color(0xFF7FB6EA) : Tokens.rio,
            secondary: Tokens.sol,
            tertiary: Tokens.copa,
            surface: dark ? Tokens.noiteSuperficie : Tokens.papel,
            onSurface: dark ? const Color(0xFFE6EEF4) : Tokens.tinta,
          );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme, brightness: scheme.brightness);
    final body = GoogleFonts.manropeTextTheme(base.textTheme);
    TextStyle? display(TextStyle? s, FontWeight w) => GoogleFonts.sora(textStyle: s, fontWeight: w);

    final weightBoost = sunMode ? FontWeight.w800 : FontWeight.w600;
    final text = body.copyWith(
      displayLarge: display(body.displayLarge, FontWeight.w700),
      displayMedium: display(body.displayMedium, FontWeight.w700),
      displaySmall: display(body.displaySmall, FontWeight.w700),
      headlineMedium: display(body.headlineMedium, FontWeight.w700),
      headlineSmall: display(body.headlineSmall, FontWeight.w700),
      titleLarge: display(body.titleLarge, FontWeight.w600),
      titleMedium: body.titleMedium?.copyWith(fontWeight: weightBoost),
      bodyLarge: body.bodyLarge?.copyWith(fontWeight: sunMode ? FontWeight.w600 : null, height: 1.45),
      bodyMedium: body.bodyMedium?.copyWith(fontWeight: sunMode ? FontWeight.w600 : null, height: 1.45),
      labelLarge: body.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    final border = sunMode
        ? const BorderSide(color: Colors.black, width: 2)
        : BorderSide(color: scheme.outlineVariant);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: sunMode ? Colors.white : (dark ? Tokens.noite : Tokens.nevoa),
      extensions: [ThermoVisuals(sunMode: sunMode)],
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(64, sunMode ? 60 : 52),
          textStyle: text.labelLarge?.copyWith(fontSize: sunMode ? 18 : 16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusControl)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: Size(64, sunMode ? 60 : 52),
          side: border,
          textStyle: text.labelLarge,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Tokens.radiusControl)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: sunMode ? Colors.white : scheme.surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(Tokens.radiusControl), borderSide: border),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Tokens.radiusControl), borderSide: border),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
          borderSide: BorderSide(color: scheme.primary, width: 2.5),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        side: border,
        shape: const StadiumBorder(),
        labelStyle: text.labelLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusBlock),
          side: sunMode ? border : BorderSide.none,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surface,
        showDragHandle: true,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
          side: sunMode ? border : BorderSide.none,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: sunMode ? Colors.white : scheme.surface,
        indicatorColor: sunMode ? Colors.black : scheme.primaryContainer,
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) && sunMode ? Colors.white : scheme.onSurface,
              size: sunMode ? 30 : 24,
            )),
        labelTextStyle: WidgetStatePropertyAll(text.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
      ),
      dividerTheme: DividerThemeData(color: sunMode ? Colors.black : scheme.outlineVariant, thickness: sunMode ? 2 : 1),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
