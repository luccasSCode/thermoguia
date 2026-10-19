import 'dart:convert';
import 'dart:math';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../app_deps.dart';
import 'guardian_api.dart' show publicBase;

/// Para onde o navegador volta depois do login: o app captura este endereço.
const appRedirect = 'thermoguia://auth';

/// Login com Google e Facebook pelo navegador (OAuth com código).
///
/// O app abre `/auth/{provedor}/start`; o provedor devolve o código em
/// `/auth/{provedor}/callback`; o servidor troca o código pelos dados da pessoa,
/// cria ou encontra a conta e volta para o app com o token de sessão. Assim as
/// chaves secretas ficam só no servidor e o app não precisa de SDK de cada rede.
void registerSocialAuthRoutes(Router r, AppDeps d) {
  bool configured(String p) => switch (p) {
        'google' => d.config.googleClientId.isNotEmpty && d.config.googleClientSecret.isNotEmpty,
        'facebook' => d.config.facebookAppId.isNotEmpty && d.config.facebookAppSecret.isNotEmpty,
        _ => false,
      };

  Response back(Map<String, String> params) =>
      Response.found(Uri.parse(appRedirect).replace(queryParameters: params).toString());

  String callbackUrl(Request req, String p) => '${publicBase(d, req)}/auth/$p/callback';

  r.get('/auth/<provider>/start', (Request req, String provider) {
    if (!configured(provider)) return back({'error': 'nao_configurado'});
    final persona = Persona.fromName(req.url.queryParameters['persona']).name;
    // O "state" assinado impede que outro site injete um login no app.
    final state = JWT({'p': provider, 'persona': persona, 'n': Random.secure().nextInt(1 << 31)})
        .sign(SecretKey(d.config.jwtSecret), expiresIn: const Duration(minutes: 10));
    final uri = provider == 'google'
        ? Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
            'client_id': d.config.googleClientId,
            'redirect_uri': callbackUrl(req, provider),
            'response_type': 'code',
            'scope': 'openid email profile',
            'state': state,
            'prompt': 'select_account',
          })
        : Uri.https('www.facebook.com', '/v19.0/dialog/oauth', {
            'client_id': d.config.facebookAppId,
            'redirect_uri': callbackUrl(req, provider),
            'response_type': 'code',
            'scope': 'email,public_profile',
            'state': state,
          });
    return Response.found(uri.toString());
  });

  r.get('/auth/<provider>/callback', (Request req, String provider) async {
    final q = req.url.queryParameters;
    if (q['error'] != null) return back({'error': 'cancelado'});
    String persona;
    try {
      final jwt = JWT.verify(q['state'] ?? '', SecretKey(d.config.jwtSecret));
      final payload = jwt.payload as Map;
      if (payload['p'] != provider) throw const FormatException();
      persona = '${payload['persona']}';
    } catch (_) {
      return back({'error': 'expirado'});
    }

    final ({String id, String? email, String name})? who;
    try {
      who = provider == 'google'
          ? await _google(d, q['code'] ?? '', callbackUrl(req, provider))
          : await _facebook(d, q['code'] ?? '', callbackUrl(req, provider));
    } catch (_) {
      return back({'error': 'falhou'});
    }
    if (who == null) return back({'error': 'falhou'});

    final column = provider == 'google' ? 'google_sub' : 'facebook_id';
    var user = await d.db.one('SELECT * FROM users WHERE $column = @id', {'id': who.id});
    // Mesmo e-mail de uma conta existente: liga o provedor a ela.
    if (user == null && who.email != null) {
      user = await d.db.one(
        'UPDATE users SET $column = @id, is_anonymous = false WHERE email = @e RETURNING *',
        {'id': who.id, 'e': who.email!.toLowerCase()},
      );
    }
    var created = false;
    if (user == null) {
      user = await d.db.one(
        '''INSERT INTO users (email, name, persona, is_anonymous, $column)
           VALUES (@e, @n, @p, false, @id) RETURNING *''',
        {'e': who.email?.toLowerCase(), 'n': who.name, 'p': persona, 'id': who.id},
      );
      created = true;
    }
    final userId = user!['id'] as String;
    await d.audit.log(userId, created ? 'conta_criada_$provider' : 'login_$provider', source: 'servidor');
    return back({'token': d.auth.issueToken(userId), if (created) 'novo': '1'});
  });
}

Future<({String id, String? email, String name})?> _google(AppDeps d, String code, String redirect) async {
  final res = await d.client.post(Uri.https('oauth2.googleapis.com', '/token'), body: {
    'code': code,
    'client_id': d.config.googleClientId,
    'client_secret': d.config.googleClientSecret,
    'redirect_uri': redirect,
    'grant_type': 'authorization_code',
  }).timeout(const Duration(seconds: 15));
  if (res.statusCode != 200) return null;
  final idToken = (jsonDecode(res.body) as Map)['id_token'] as String?;
  if (idToken == null) return null;
  // O id_token veio direto do Google por HTTPS nesta troca: basta ler o conteúdo.
  final claims = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(idToken.split('.')[1])))) as Map;
  if (claims['aud'] != d.config.googleClientId) return null;
  final verified = claims['email_verified'] == true || claims['email_verified'] == 'true';
  return (
    id: '${claims['sub']}',
    email: verified ? claims['email'] as String? : null,
    name: '${claims['given_name'] ?? claims['name'] ?? ''}',
  );
}

Future<({String id, String? email, String name})?> _facebook(AppDeps d, String code, String redirect) async {
  final tok = await d.client
      .get(Uri.https('graph.facebook.com', '/v19.0/oauth/access_token', {
        'client_id': d.config.facebookAppId,
        'client_secret': d.config.facebookAppSecret,
        'redirect_uri': redirect,
        'code': code,
      }))
      .timeout(const Duration(seconds: 15));
  if (tok.statusCode != 200) return null;
  final access = (jsonDecode(tok.body) as Map)['access_token'] as String?;
  if (access == null) return null;
  final me = await d.client.get(Uri.https('graph.facebook.com', '/v19.0/me', {
    'fields': 'id,first_name,email',
    'access_token': access,
  })).timeout(const Duration(seconds: 15));
  if (me.statusCode != 200) return null;
  final m = jsonDecode(me.body) as Map;
  return (id: '${m['id']}', email: m['email'] as String?, name: '${m['first_name'] ?? ''}');
}
