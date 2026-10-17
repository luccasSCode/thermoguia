import 'package:flutter/material.dart';

/// Logo oficial (folha inclinada) no próprio quadro arredondado do ícone,
/// então funciona sobre o tema claro e o escuro sem moldura.
class ThermoLogo extends StatelessWidget {
  const ThermoLogo({super.key, this.size = 96});
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/branding/logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: 'ThermoGuia Manaus',
      );
}
