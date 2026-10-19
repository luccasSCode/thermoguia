import 'package:flutter/services.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/config/app_config.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/local_store.dart';
import '../domain/app_user.dart';

class AuthRepository {
  AuthRepository(this._api, this._store);
  final ApiClient _api;
  final LocalStore _store;
  static const _userKey = 'cached_user';

  AppUser? get cachedUser {
    final m = _store.readMap(_userKey);
    return m == null ? null : AppUser.fromJson(m);
  }

  bool get hasToken => _store.token != null;

  Future<AppUser> _session(dynamic data) async {
    final map = (data as Map).cast<String, dynamic>();
    await _store.setToken(map['token'] as String);
    return _cache(map['user']);
  }

  Future<AppUser> _cache(dynamic json) async {
    final user = AppUser.fromJson((json as Map).cast<String, dynamic>());
    await _store.writeMap(_userKey, user.toJson());
    return user;
  }

  Future<AppUser> startAnonymous(String name, Persona persona) async =>
      _session(await _api.post('/auth/anonymous', {'name': name, 'persona': persona.name}));

  Future<AppUser> login(String email, String password) async =>
      _session(await _api.post('/auth/login', {'email': email, 'password': password}));

  Future<AppUser> register(String name, String email, String password, Persona persona) async =>
      _session(await _api.post('/auth/register', {
        'name': name,
        'email': email,
        'password': password,
        'persona': persona.name,
      }));

  /// Login com Google ou Facebook pelo navegador seguro do sistema. O servidor
  /// conduz o OAuth e volta para `thermoguia://auth` com o token de sessão.
  /// Devolve null se a pessoa fechar a tela de login.
  Future<AppUser?> socialLogin(String provider, String brand, {Persona? persona}) async {
    final start = Uri.parse('${AppConfig.apiUrl}/auth/$provider/start')
        .replace(queryParameters: {if (persona != null) 'persona': persona.name});
    final String result;
    try {
      result = await FlutterWebAuth2.authenticate(url: start.toString(), callbackUrlScheme: 'thermoguia');
    } on PlatformException catch (e) {
      if (e.code == 'CANCELED') return null;
      throw ApiException('Não foi possível abrir o login com $brand.');
    } catch (_) {
      // Sem navegador de login disponível (plugin ausente, aparelho sem suporte).
      throw ApiException('Não foi possível abrir o login com $brand.');
    }
    final q = Uri.parse(result).queryParameters;
    final token = q['token'];
    if (token == null) {
      throw ApiException(switch (q['error']) {
        'nao_configurado' => 'O login com $brand ainda não foi ativado no servidor do ThermoGuia. '
            'Por enquanto, toque em "Começar" ou entre com seu e-mail.',
        'cancelado' => 'Login com $brand cancelado.',
        'expirado' => 'O login demorou demais. Tente de novo.',
        _ => 'Não foi possível entrar com $brand. Tente de novo.',
      });
    }
    await _store.setToken(token);
    return me();
  }

  Future<AppUser> me() async => _cache(await _api.get('/me'));

  Future<AppUser> update({String? name, Persona? persona}) async => _cache(await _api.patch('/me', {
        if (name != null) 'name': name,
        if (persona != null) 'persona': persona.name,
      }));

  Future<AppUser> addCredentials(String email, String password) async =>
      _cache(await _api.post('/me/credentials', {'email': email, 'password': password}));

  Future<AppUser> setAvatar(List<int> jpeg) async => _cache(await _api.putBytes('/me/avatar', jpeg, 'image/jpeg'));

  Future<AppUser> removeAvatar() async => _cache(await _api.delete('/me/avatar'));

  Future<void> deleteAccount() async {
    await _api.delete('/me');
    await _store.clearAll();
  }

  Future<void> signOut() => _store.clearAll();
}
