import 'package:http/http.dart' as http;

import 'cities.dart';
import 'config.dart';
import 'data/db.dart';
import 'data/repositories.dart';
import 'services/air_quality_service.dart';
import 'services/assistant_service.dart';
import 'services/auth_service.dart';
import 'services/claude_service.dart';
import 'services/geocoding_service.dart';
import 'services/green_index_service.dart';
import 'services/open_meteo_service.dart';
import 'services/rewards_service.dart';
import 'services/social_service.dart';
import 'services/verification_service.dart';
import 'services/routing_service.dart';

/// Composição de dependências (injeção manual, sem mágica).
class AppDeps {
  AppDeps._(this.config, this.db);

  final Config config;
  final Db db;
  final client = http.Client();

  late final auth = AuthService(config.jwtSecret);
  late final users = UserRepo(db);
  late final profiles = ProfileRepo(db);
  late final hydration = HydrationRepo(db);
  late final trips = TripRepo(db);
  late final contacts = ContactRepo(db);
  late final reports = ReportRepo(db);
  late final audit = AuditRepo(db);
  late final aiUsage = AiUsageRepo(db);
  late final rewards = RewardsService(RewardRepo(db));
  late final socialRepo = SocialRepo(db);
  late final verification = VerificationService(claude);
  late final social = SocialService(socialRepo, verification, rewards, users);

  late final weather = OpenMeteoService(client);
  late final air = AirQualityService(client);
  late final geocoding = GeocodingService(config, client);
  late final claude = ClaudeService(config, client);

  /// Um índice verde por cidade atendida.
  late final green = {for (final c in cities) c.id: GreenIndexService(config, client, c)};
  late final routing = {for (final c in cities) c.id: RoutingService(config, client, green[c.id]!)};
  late final assistants = {
    for (final c in cities) c.id: AssistantService(claude, weather, green[c.id]!),
  };

  static Future<AppDeps> create() async {
    final config = Config.load();
    final db = await Db.connect(config);
    return AppDeps._(config, db);
  }
}
