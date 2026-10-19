import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../rewards/rewards_controller.dart';

/// Categorias da Comunidade (as mesmas do servidor).
class CommunityCategory {
  const CommunityCategory(this.id, this.label, this.badge, this.icon, this.hint);
  final String id;
  final String label;
  final String badge;
  final IconData icon;

  /// O que a foto precisa mostrar.
  final String hint;
}

const communityCategories = [
  CommunityCategory('agua', 'Hidratação', '+ Hidratado', Icons.water_drop_outlined,
      'Duas fotos da mesma garrafa ou copo: antes de beber e pelo menos 10 minutos depois, com o rótulo ou as marcações de ml visíveis.'),
  CommunityCategory('bone', 'Boné ou chapéu', '+ Usou boné', Icons.face_retouching_natural,
      'Você com o boné ou chapéu na cabeça (não vale o boné na mão ou na mesa).'),
  CommunityCategory('protetor', 'Protetor solar', '+ Usou protetor solar', Icons.sanitizer_outlined,
      'Você aplicando o protetor na pele, ou o frasco junto da pele com o creme visível.'),
  CommunityCategory('guarda_sol', 'Guarda-sol', '+ Usou guarda-sol', Icons.beach_access_outlined,
      'Você com o guarda-sol ou guarda-chuva aberto, ao ar livre.'),
  CommunityCategory('oculos', 'Óculos de sol', '+ Usou óculos de sol', Icons.visibility_outlined,
      'Você usando óculos de sol no rosto.'),
  CommunityCategory('mascara', 'Máscara na fumaça', '+ Usou máscara', Icons.masks_outlined,
      'Você com a máscara de proteção cobrindo nariz e boca (no queixo ou na mão não vale).'),
  CommunityCategory('sombra', 'Caminho pela sombra', '+ Andou na sombra', Icons.park_outlined,
      'Você ao ar livre, na sombra de árvores, toldo ou marquise, com a sombra aparecendo.'),
  CommunityCategory('app_aberto', 'App aberto hoje', '+ Abriu o ThermoGuia', Icons.phone_iphone,
      'Print da tela inteira com o ThermoGuia aberto, mostrando a hora e a bateria no topo.'),
];

CommunityCategory categoryOf(String id) =>
    communityCategories.firstWhere((c) => c.id == id, orElse: () => communityCategories.first);

const reactionKinds = <(String, String, String)>[
  ('curtir', '👍', 'Curtir'),
  ('hidratado', '💧', 'Hidratado'),
  ('protegido', '🧴', 'Protegido'),
  ('inspirou', '✨', 'Me inspirou'),
];

typedef Post = Map<String, dynamic>;

/// Feed paginado: só posts aprovados (verificados).
class FeedController extends AsyncNotifier<List<Post>> {
  bool _end = false;

  @override
  Future<List<Post>> build() async {
    _end = false;
    return _fetch(null);
  }

  Future<List<Post>> _fetch(String? before) async {
    final list = await ref.read(apiClientProvider).get('/social/feed', query: {if (before != null) 'before': before}) as List;
    if (list.length < 20) _end = true;
    return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
  }

  Future<void> refresh() async => state = await AsyncValue.guard(build);

  Future<void> loadMore() async {
    final cur = state.valueOrNull;
    if (_end || cur == null || cur.isEmpty || state.isLoading) return;
    final more = await _fetch('${cur.last['createdAt']}');
    state = AsyncData([...cur, ...more]);
  }

  /// Atualiza um post (reação) sem recarregar o feed.
  void replace(Post p) {
    final cur = state.valueOrNull;
    if (cur == null) return;
    state = AsyncData([for (final x in cur) x['id'] == p['id'] ? p : x]);
  }

  void remove(String id) {
    final cur = state.valueOrNull;
    if (cur != null) state = AsyncData(cur.where((x) => x['id'] != id).toList());
  }
}

final feedProvider = AsyncNotifierProvider<FeedController, List<Post>>(FeedController.new);

final myPostsProvider = FutureProvider.autoDispose<List<Post>>((ref) async {
  final list = await ref.read(apiClientProvider).get('/social/mine') as List;
  return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
});

final badgesProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async =>
    ((await ref.read(apiClientProvider).get('/social/badges')) as Map).cast<String, dynamic>());

/// Fotos e avatares vêm com login; ficam em memória enquanto o app está aberto.
final postImageProvider = FutureProvider.family<Uint8List, (String, String)>((ref, key) async =>
    Uint8List.fromList(await ref.read(apiClientProvider).getBytes('/social/posts/${key.$1}/image/${key.$2}')));

final userAvatarProvider = FutureProvider.family<Uint8List?, (String, String?)>((ref, key) async {
  if (key.$2 == null) return null;
  try {
    return Uint8List.fromList(await ref.read(apiClientProvider).getBytes('/social/users/${key.$1}/avatar'));
  } catch (_) {
    return null;
  }
});

/// Ações da Comunidade.
class CommunityActions {
  CommunityActions(this.ref);
  final Ref ref;

  /// As provas valem com a câmera, na hora. A galeria só é liberada nas
  /// versões de desenvolvimento (o simulador não tem câmera).
  Future<Uint8List?> takePhoto({bool fromGallery = false}) async {
    final picked = await ImagePicker().pickImage(
      source: fromGallery ? ImageSource.gallery : ImageSource.camera,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 85,
      requestFullMetadata: false,
    );
    return picked == null ? null : await picked.readAsBytes();
  }

  Future<Post> publish(String category, String caption, Uint8List photo) async => _post(
      await ref.read(apiClientProvider).post('/social/posts', {
        'category': category,
        'caption': caption,
        'image': base64Encode(photo),
      }));

  Future<Post> startWater(Uint8List before) async =>
      _post(await ref.read(apiClientProvider).post('/social/water', {'image': base64Encode(before)}));

  Future<Post> finishWater(String id, String caption, Uint8List after) async => _post(await ref
      .read(apiClientProvider)
      .post('/social/water/$id/finish', {'caption': caption, 'image': base64Encode(after)}));

  Post _post(Object? res) {
    ref.invalidate(myPostsProvider);
    return (res as Map).cast<String, dynamic>();
  }

  Future<Post> react(Post p, String? kind) async {
    final api = ref.read(apiClientProvider);
    if (kind == null || kind == p['myReaction']) {
      await api.delete('/social/posts/${p['id']}/reaction');
    } else {
      await api.put('/social/posts/${p['id']}/reaction', {'kind': kind});
    }
    final fresh = ((await api.get('/social/posts/${p['id']}')) as Map).cast<String, dynamic>();
    ref.read(feedProvider.notifier).replace(fresh);
    return fresh;
  }

  Future<void> delete(String id) async {
    await ref.read(apiClientProvider).delete('/social/posts/$id');
    ref.read(feedProvider.notifier).remove(id);
    ref.invalidate(myPostsProvider);
  }

  Future<void> report(String type, String id, String reason) =>
      ref.read(apiClientProvider).post('/social/report', {'type': type, 'id': id, 'reason': reason});

  Future<void> block(String userId) async {
    await ref.read(apiClientProvider).post('/social/users/$userId/block');
    await ref.read(feedProvider.notifier).refresh();
  }

  /// Saldo do Clube H2O muda quando um post é aprovado.
  void refreshRewards() => ref.read(rewardsProvider.notifier).refresh();
}

final communityActionsProvider = Provider((ref) => CommunityActions(ref));
