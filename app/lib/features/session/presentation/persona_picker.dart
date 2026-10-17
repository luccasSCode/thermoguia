import 'package:flutter/material.dart';
import 'package:thermo_core/thermo_core.dart';

IconData personaIcon(Persona p) => switch (p) {
      Persona.pedestre => Icons.directions_walk,
      Persona.ciclista => Icons.directions_bike,
      Persona.entregador => Icons.delivery_dining,
      Persona.vendedor => Icons.storefront_outlined,
      Persona.carteiro => Icons.markunread_mailbox_outlined,
      Persona.idoso => Icons.elderly,
    };

class PersonaPicker extends StatelessWidget {
  const PersonaPicker({super.key, required this.value, required this.onChanged});
  final Persona value;
  final ValueChanged<Persona> onChanged;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in Persona.values)
            ChoiceChip(
              avatar: Icon(personaIcon(p), size: 20),
              label: Text(p.label),
              selected: p == value,
              onSelected: (_) => onChanged(p),
            ),
        ],
      );
}
