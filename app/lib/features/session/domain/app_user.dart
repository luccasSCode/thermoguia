import 'package:thermo_core/thermo_core.dart';

class AppUser {
  const AppUser({
    required this.id,
    required this.name,
    required this.persona,
    required this.plan,
    required this.isAnonymous,
    this.email,
    this.avatarVersion,
  });

  final String id;
  final String name;
  final String? email;
  final Persona persona;
  final String plan;
  final bool isAnonymous;

  /// Data da foto de perfil atual (null = sem foto). Muda a cada troca.
  final String? avatarVersion;
  bool get hasAvatar => avatarVersion != null;

  bool get isPlus => plan == 'plus';
  String get firstName => name.trim().isEmpty ? '' : name.trim().split(' ').first;

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        email: j['email'] as String?,
        persona: Persona.fromName(j['persona'] as String?),
        plan: j['plan'] as String? ?? 'free',
        isAnonymous: j['isAnonymous'] as bool? ?? false,
        avatarVersion: j['avatarUpdatedAt'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'email': email,
        'persona': persona.name,
        'plan': plan,
        'isAnonymous': isAnonymous,
        'avatarUpdatedAt': avatarVersion,
      };
}
