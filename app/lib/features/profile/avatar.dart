import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../session/presentation/persona_picker.dart';
import '../session/presentation/session_controller.dart';

/// Foto de perfil. Guardada no servidor (vale em qualquer aparelho) e em
/// cache local por versão, para abrir rápido e sem internet.
final avatarProvider = FutureProvider<Uint8List?>((ref) async {
  final version = ref.watch(sessionProvider.select((s) => s.user?.avatarVersion));
  if (version == null) return null;
  final store = ref.read(localStoreProvider);
  final key = 'avatar_$version';
  final cached = store.getString(key);
  if (cached != null) return base64Decode(cached);
  final bytes = Uint8List.fromList(await ref.read(apiClientProvider).getBytes('/me/avatar'));
  // Só a versão atual fica guardada.
  for (final k in store.keysWithPrefix('avatar_')) {
    await store.remove(k);
  }
  await store.setString(key, base64Encode(bytes));
  return bytes;
});

/// Foto da pessoa ou, sem foto, o ícone do perfil de deslocamento.
class UserAvatar extends ConsumerWidget {
  const UserAvatar({super.key, this.radius = 24});
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(sessionProvider.select((s) => s.user));
    final photo = ref.watch(avatarProvider).valueOrNull;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Tokens.rio.withValues(alpha: 0.15),
      foregroundImage: photo == null ? null : MemoryImage(photo),
      child: Icon(user == null ? Icons.person_outline : personaIcon(user.persona), size: radius, color: Tokens.rio),
    );
  }
}

/// Opções: tirar foto, escolher da galeria ou remover.
Future<void> changeAvatar(BuildContext context, WidgetRef ref) async {
  final hasPhoto = ref.read(sessionProvider).user?.hasAvatar ?? false;
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Tirar foto'),
          onTap: () => Navigator.pop(ctx, 'camera'),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Escolher da galeria'),
          onTap: () => Navigator.pop(ctx, 'galeria'),
        ),
        if (hasPhoto)
          ListTile(
            leading: Icon(Icons.delete_outline, color: Theme.of(ctx).colorScheme.error),
            title: Text('Remover foto', style: TextStyle(color: Theme.of(ctx).colorScheme.error)),
            onTap: () => Navigator.pop(ctx, 'remover'),
          ),
      ]),
    ),
  );
  if (choice == null || !context.mounted) return;
  final session = ref.read(sessionProvider);
  try {
    if (choice == 'remover') {
      await session.removeAvatar();
      if (context.mounted) showMessage(context, 'Foto removida.');
      return;
    }
    final picked = await ImagePicker().pickImage(
      source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
      preferredCameraDevice: CameraDevice.front,
      // Reduz no aparelho: ~50 KB, rápido de enviar mesmo com 3G.
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 80,
      requestFullMetadata: false,
    );
    if (picked == null) return;
    await session.setAvatar(await picked.readAsBytes());
    if (context.mounted) showMessage(context, 'Foto atualizada.');
  } catch (e) {
    if (context.mounted) {
      showMessage(
        context,
        e.toString().contains('access_denied') || e.toString().contains('camera_access')
            ? 'Sem permissão para usar a câmera ou as fotos. Libere nos Ajustes do aparelho.'
            : errorText(e),
      );
    }
  }
}
