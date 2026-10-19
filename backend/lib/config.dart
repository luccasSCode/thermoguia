import 'package:dotenv/dotenv.dart';

class Config {
  Config._(this._env);
  final DotEnv _env;

  factory Config.load() =>
      Config._(DotEnv(includePlatformEnvironment: true)..load());

  /// Só os valores padrão, sem .env nem variáveis do sistema (para testes).
  factory Config.defaults() => Config._(DotEnv(includePlatformEnvironment: false));

  String _s(String k, String d) {
    final v = _env[k];
    return (v == null || v.isEmpty) ? d : v;
  }

  int get port => int.parse(_s('PORT', '8080'));
  String get dbHost => _s('DB_HOST', 'localhost');
  int get dbPort => int.parse(_s('DB_PORT', '5432'));
  String get dbName => _s('DB_NAME', 'thermoguia');
  String get dbUser => _s('DB_USER', 'thermoguia');
  String get dbPassword => _s('DB_PASSWORD', 'thermoguia');
  String get jwtSecret => _s('JWT_SECRET', 'dev-secret');
  String get anthropicApiKey => _s('ANTHROPIC_API_KEY', '');
  String get anthropicModel => _s('ANTHROPIC_MODEL', 'claude-haiku-5-5');
  /// Verificação das fotos da Comunidade: modelo com visão de alta precisão.
  String get anthropicVisionModel => _s('ANTHROPIC_VISION_MODEL', 'claude-opus-5-5');

  /// Chave das rotas /admin (fila de revisão humana). Vazia = rotas desligadas.
  String get adminToken => _s('ADMIN_TOKEN', '');
  int get freeAiDailyLimit => int.parse(_s('FREE_AI_DAILY_LIMIT', '15'));
  int get plusAiDailyLimit => 300;
  String get routingFootUrl => _s('ROUTING_FOOT_URL', 'https://routing.openstreetmap.de/routed-foot');
  String get routingBikeUrl => _s('ROUTING_BIKE_URL', 'https://routing.openstreetmap.de/routed-bike');

  /// Malha de ruas de carro: só o plano B quando o mapa a pé/bicicleta não liga
  /// os dois pontos (ex.: Ponta Negra). O usuário nunca escolhe "carro".
  String get routingCarUrl => _s('ROUTING_CAR_URL', 'https://routing.openstreetmap.de/routed-car');
  String get overpassUrl => _s('OVERPASS_URL', 'https://overpass-api.de/api/interpreter');
  String get nominatimUrl => _s('NOMINATIM_URL', 'https://nominatim.openstreetmap.org');
  String get cacheDir => _s('CACHE_DIR', 'cache');
  String get contactEmail => _s('CONTACT_EMAIL', 'contato@thermoguia.app');

  /// Endereço público da API (links do responsável e retorno do login social).
  /// O Render preenche RENDER_EXTERNAL_URL sozinho; vazio = usa o da requisição.
  String get publicUrl => _s('PUBLIC_URL', _s('RENDER_EXTERNAL_URL', ''));

  /// Login social: credenciais OAuth "Aplicativo da Web" de cada provedor.
  String get googleClientId => _s('GOOGLE_CLIENT_ID', '');
  String get googleClientSecret => _s('GOOGLE_CLIENT_SECRET', '');
  String get facebookAppId => _s('FACEBOOK_APP_ID', '');
  String get facebookAppSecret => _s('FACEBOOK_APP_SECRET', '');

  /// Exigido pelas políticas de uso do OpenStreetMap.
  String get userAgent => 'ThermoGuia/1.0 ($contactEmail)';
}
