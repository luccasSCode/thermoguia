import 'package:flutter/material.dart';
import 'package:thermo_core/thermo_core.dart';

/// Paleta derivada da logo: o azul do rio, o laranja do sol e o verde
/// das copas (usado só para sombra e Rotas Frescas, para ter significado).
abstract final class Tokens {
  static const rio = Color(0xFF1D6CB3);
  static const rioProfundo = Color(0xFF0E3F6E);
  static const sol = Color(0xFFF28C34);
  static const copa = Color(0xFF2D7A57);
  static const tinta = Color(0xFF13212E);
  static const nevoa = Color(0xFFEEF3F7);
  static const papel = Color(0xFFFFFFFF);
  static const pedra = Color(0xFF5C6B78);

  static const noite = Color(0xFF0F1A24);
  static const noiteSuperficie = Color(0xFF172633);

  static Color risk(RiskLevel l, {bool sunMode = false}) => switch (l) {
        RiskLevel.baixo => sunMode ? const Color(0xFF145C3B) : copa,
        RiskLevel.moderado => sunMode ? const Color(0xFF7A5C00) : const Color(0xFFC79A1E),
        RiskLevel.alto => sunMode ? const Color(0xFF9A4A00) : sol,
        RiskLevel.muitoAlto => sunMode ? const Color(0xFF8E2A0E) : const Color(0xFFD9542B),
        RiskLevel.extremo => sunMode ? const Color(0xFF6E0F0B) : const Color(0xFFA8231F),
      };

  /// Cor de um trecho de rota conforme a sombra (0–1).
  static Color shade(double s) => s >= 0.55
      ? copa
      : s >= 0.3
          ? const Color(0xFFC79A1E)
          : sol;

  /// Degradê verde da logo (menta → verde → petróleo), da esquerda para a direita.
  static const logoGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF76CEAD), Color(0xFF2EA586), Color(0xFF004A50)],
  );

  static const radiusSheet = 28.0;
  static const radiusBlock = 20.0;
  static const radiusControl = 14.0;
}
