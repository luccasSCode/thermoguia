import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/network/api_client.dart';
import '../../../core/providers.dart';
import '../data/auth_repository.dart';
import '../domain/app_user.dart';

enum SessionStatus { loading, signedOut, signedIn }

/// Estado da sessão. É um ChangeNotifier para alimentar o redirecionamento
/// do go_router.
class SessionController extends ChangeNotifier {
  SessionController(this._repo);
  final AuthRepository _repo;

  SessionStatus status = SessionStatus.loading;
  AppUser? user;

  Future<void> restore() async {
    if (!_repo.hasToken) {
      _set(SessionStatus.signedOut, null);
      return;
    }
    // Abre na hora com o usuário em cache; atualiza do servidor em seguida.
    final cached = _repo.cachedUser;
    if (cached != null) _set(SessionStatus.signedIn, cached);
    try {
      _set(SessionStatus.signedIn, await _repo.me());
    } on ApiException catch (e) {
      if (e.status == 401) {
        await _repo.signOut();
        _set(SessionStatus.signedOut, null);
      } else if (cached == null) {
        _set(SessionStatus.signedOut, null);
      }
    }
  }

  Future<void> startAnonymous(String name, Persona persona) async =>
      _set(SessionStatus.signedIn, await _repo.startAnonymous(name, persona));

  Future<void> login(String email, String password) async =>
      _set(SessionStatus.signedIn, await _repo.login(email, password));

  Future<void> register(String name, String email, String password, Persona persona) async =>
      _set(SessionStatus.signedIn, await _repo.register(name, email, password, persona));

  Future<void> update({String? name, Persona? persona}) async =>
      _set(SessionStatus.signedIn, await _repo.update(name: name, persona: persona));

  Future<void> setAvatar(List<int> jpeg) async => _set(SessionStatus.signedIn, await _repo.setAvatar(jpeg));

  Future<void> removeAvatar() async => _set(SessionStatus.signedIn, await _repo.removeAvatar());

  Future<void> addCredentials(String email, String password) async =>
      _set(SessionStatus.signedIn, await _repo.addCredentials(email, password));

  Future<void> signOut() async {
    await _repo.signOut();
    _set(SessionStatus.signedOut, null);
  }

  Future<void> deleteAccount() async {
    await _repo.deleteAccount();
    _set(SessionStatus.signedOut, null);
  }

  void handleUnauthorized() {
    if (status != SessionStatus.signedIn) return;
    signOut();
  }

  void _set(SessionStatus s, AppUser? u) {
    status = s;
    user = u;
    notifyListeners();
  }
}

final authRepositoryProvider = Provider(
  (ref) => AuthRepository(ref.watch(apiClientProvider), ref.watch(localStoreProvider)),
);

final sessionProvider = ChangeNotifierProvider<SessionController>((ref) {
  final controller = SessionController(ref.watch(authRepositoryProvider));
  ref.read(apiClientProvider)
    ..onUnauthorized = controller.handleUnauthorized
    ..warmUp();
  controller.restore();
  return controller;
});

/// Perfil de uso atual (pedestre por padrão).
final personaProvider = Provider<Persona>(
  (ref) => ref.watch(sessionProvider.select((s) => s.user?.persona)) ?? Persona.pedestre,
);
