import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Armazenamento local simples (preferências, cache e dados offline).
class LocalStore {
  LocalStore(this._prefs);
  final SharedPreferences _prefs;

  String? get token => _prefs.getString('auth_token');
  Future<void> setToken(String? value) =>
      value == null ? _prefs.remove('auth_token') : _prefs.setString('auth_token', value);

  Map<String, dynamic>? readMap(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeMap(String key, Map<String, dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  List<dynamic> readList(String key) {
    final raw = _prefs.getString(key);
    if (raw == null) return const [];
    try {
      return jsonDecode(raw) as List<dynamic>;
    } catch (_) {
      return const [];
    }
  }

  Future<void> writeList(String key, List<dynamic> value) =>
      _prefs.setString(key, jsonEncode(value));

  String? getString(String key) => _prefs.getString(key);
  Future<void> setString(String key, String value) => _prefs.setString(key, value);
  Future<void> remove(String key) => _prefs.remove(key);

  List<String> keysWithPrefix(String prefix) => _prefs.getKeys().where((k) => k.startsWith(prefix)).toList();

  /// Apaga todos os dados locais (sair / excluir conta).
  Future<void> clearAll() => _prefs.clear();
}
