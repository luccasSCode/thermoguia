import 'package:test/test.dart';
import 'package:thermo_core/thermo_core.dart';

void main() {
  // Rua reta de 200 m para o leste, depois 100 m para o norte.
  const a = GeoPoint(-3.1300, -60.0250);
  final b = offsetPoint(a, 90, 200);
  final c = offsetPoint(b, 0, 100);
  final line = RouteLine([a, b, c]);

  test('rumo e lado', () {
    expect(bearingDeg(a, b), closeTo(90, 0.5));
    expect(angleDiff(90, 0), -90); // norte fica à esquerda de quem vai para o leste
    expect(angleDiff(90, 180), 90);
  });

  test('comprimento e projeção', () {
    expect(line.length, closeTo(300, 2));
    final p = offsetPoint(offsetPoint(a, 90, 50), 0, 8); // 50 m adiante, 8 m ao lado
    final fix = line.project(p);
    expect(fix.along, closeTo(50, 2));
    expect(fix.offset, closeTo(8, 1));
    final p2 = offsetPoint(b, 0, 40);
    expect(line.project(p2, hint: 0).along, closeTo(240, 2));
  });

  test('ponto e rumo a uma distância', () {
    final (p, brg) = line.at(250);
    expect(distanceMeters(p, offsetPoint(b, 0, 50)), lessThan(2));
    expect(brg, closeTo(0, 1));
  });

  test('instruções em português', () {
    Maneuver m(String type, String mod, {String street = '', int? exit}) =>
        Maneuver(type: type, modifier: mod, street: street, point: a, along: 0, exit: exit);
    expect(m('turn', 'right', street: 'Rua Recife').instruction, 'Vire à direita na Rua Recife');
    expect(m('turn', 'slight left').instruction, 'Mantenha-se à esquerda');
    expect(m('roundabout', '', street: 'Av. Djalma Batista', exit: 2).instruction,
        'Na rotatória, pegue a 2ª saída para a Av. Djalma Batista');
    expect(m('new name', 'straight', street: 'Rua 10').instruction, 'Continue em frente pela Rua 10');
    expect(m('arrive', '').instruction, 'Você chegou ao destino');
    expect(m('end of road', 'left').instruction, 'No fim da rua, vire à esquerda');
  });

  test('distância falada', () {
    expect(spokenDistance(47), 'Em 50 metros');
    expect(spokenDistance(4), 'Em 10 metros');
    expect(spokenDistance(320), 'Em 300 metros');
    expect(spokenDistance(1240), 'Em 1,2 quilômetros');
    expect(spokenDistance(1000), 'Em 1 quilômetro');
  });

  test('trechos contínuos', () {
    final pts = [for (var i = 0; i <= 20; i++) offsetPoint(a, 90, i * 10.0)];
    final l = RouteLine(pts);
    final flags = [for (var i = 0; i <= 20; i++) i >= 5 && i <= 14];
    expect(runsWhere(l, flags, minM: 60), [(5, 14)]);
    expect(runsWhere(l, flags, minM: 120), isEmpty);
  });
}
