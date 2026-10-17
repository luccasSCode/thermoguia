import 'package:flutter_test/flutter_test.dart';
import 'package:thermoguia/features/home/greeting.dart';

void main() {
  DateTime at(int h, int m) => DateTime(2026, 10, 14, h, m);

  test('saudação segue o horário', () {
    expect(DayPeriod.of(at(0, 0)).greeting, 'Boa madrugada');
    expect(DayPeriod.of(at(5, 59)).greeting, 'Boa madrugada');
    expect(DayPeriod.of(at(6, 0)).greeting, 'Bom dia');
    expect(DayPeriod.of(at(11, 59)).greeting, 'Bom dia');
    expect(DayPeriod.of(at(12, 0)).greeting, 'Boa tarde');
    expect(DayPeriod.of(at(17, 59)).greeting, 'Boa tarde');
    expect(DayPeriod.of(at(18, 0)).greeting, 'Boa noite');
    expect(DayPeriod.of(at(23, 59)).greeting, 'Boa noite');
  });

  test('próxima virada', () {
    expect(DayPeriod.nextChange(at(3, 10)), at(6, 0));
    expect(DayPeriod.nextChange(at(11, 59)), at(12, 0));
    expect(DayPeriod.nextChange(at(17, 0)), at(18, 0));
    expect(DayPeriod.nextChange(at(22, 30)), DateTime(2026, 10, 15));
  });
}
