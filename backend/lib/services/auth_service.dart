import 'package:bcrypt/bcrypt.dart';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

import '../http/http_utils.dart';

class AuthService {
  AuthService(this._secret);
  final String _secret;

  String hashPassword(String password) => BCrypt.hashpw(password, BCrypt.gensalt());

  bool checkPassword(String password, String hash) {
    try {
      return BCrypt.checkpw(password, hash);
    } catch (_) {
      return false;
    }
  }

  String issueToken(String userId) => JWT({'sub': userId}, issuer: 'thermoguia')
      .sign(SecretKey(_secret), expiresIn: const Duration(days: 60));

  String verifyToken(String token) {
    try {
      final jwt = JWT.verify(token, SecretKey(_secret));
      final sub = (jwt.payload as Map)['sub'];
      if (sub is String && sub.isNotEmpty) return sub;
    } catch (_) {}
    throw ApiError(401, 'Sessão expirada. Entre novamente.');
  }
}
