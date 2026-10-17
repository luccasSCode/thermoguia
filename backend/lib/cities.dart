import 'package:thermo_core/thermo_core.dart';

/// Cidades atendidas. Para expandir, basta adicionar uma entrada aqui;
/// o índice de áreas verdes é gerado automaticamente para o novo recorte.
class City {
  const City({
    required this.id,
    required this.name,
    required this.state,
    required this.center,
    required this.bounds,
    required this.utcOffsetHours,
    this.active = true,
  });

  final String id;
  final String name;
  final String state;
  final GeoPoint center;
  final GeoBounds bounds;
  final int utcOffsetHours;
  final bool active;

  Duration get utcOffset => Duration(hours: utcOffsetHours);

  /// Converte um instante para "hora de parede" local da cidade.
  DateTime localWallClock(DateTime t) => t.toUtc().add(utcOffset);

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'state': state,
        'center': center.toJson(),
        'bounds': bounds.toJson(),
        'utcOffsetHours': utcOffsetHours,
        'active': active,
      };
}

const manaus = City(
  id: 'manaus',
  name: 'Manaus',
  state: 'AM',
  center: GeoPoint(-3.1190, -60.0217),
  bounds: GeoBounds(-3.17, -60.12, -2.92, -59.86),
  utcOffsetHours: -4,
);

const cities = <City>[manaus];

City cityById(String? id) => cities.firstWhere((c) => c.id == id, orElse: () => manaus);
