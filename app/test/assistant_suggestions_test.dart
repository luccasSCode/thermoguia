import 'package:flutter_test/flutter_test.dart';
import 'package:thermo_core/thermo_core.dart';
import 'package:thermoguia/features/assistant/assistant_suggestions.dart';

void main() {
  const ctx = SuggestionContext(persona: Persona.pedestre, night: false, rain: false, hot: false);

  test('a rolagem alterna calor e fumaça, sem repetir perguntas', () {
    final shown = <String>{};
    final pages = <List<Suggestion>>[];
    for (var page = 1; page < 20; page++) {
      final batch = moreSuggestions(ctx, page: page, skip: shown);
      if (batch.isEmpty) break;
      pages.add(batch);
      for (final s in batch) {
        expect(shown.add(s.text), isTrue, reason: 'repetiu: ${s.text}');
      }
    }
    expect(pages.length, greaterThanOrEqualTo(6), reason: 'banco grande o bastante para rolar');
    // Cada lote cheio traz os dois assuntos.
    for (final b in pages.where((b) => b.length == 6).take(4)) {
      expect(b.map((s) => s.topic).toSet(), {Topic.calor, Topic.fumaca});
    }
  });

  test('perguntas de outro perfil e de noite não aparecem de dia para pedestre', () {
    final all = <Suggestion>[];
    for (var page = 1; page < 20; page++) {
      final batch = moreSuggestions(ctx, page: page, skip: {for (final s in all) s.text});
      if (batch.isEmpty) break;
      all.addAll(batch);
    }
    expect(all.any((s) => s.personas.isNotEmpty && !s.personas.contains(Persona.pedestre)), isFalse);
    expect(all.any((s) => s.when == When.noite), isFalse);
    // Sem fumaça agora, as perguntas de fumaça também aparecem na rolagem.
    expect(all.any((s) => s.text == 'Por que tem tanta fumaça em Manaus?'), isTrue);
  });
}
