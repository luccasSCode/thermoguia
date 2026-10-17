import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:thermoguia/core/widgets/heat_band.dart';

void main() {
  testWidgets('faixa térmica expõe o risco para leitores de tela', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: HeatBand(score: 72, level: RiskLevel.muitoAlto)),
    ));
    expect(find.bySemanticsLabel('Risco Muito alto, 72 de 100'), findsOneWidget);
  });
}
