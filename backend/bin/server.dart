import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:thermoguia_backend/api/account_api.dart';
import 'package:thermoguia_backend/api/assistant_api.dart';
import 'package:thermoguia_backend/api/guardian_api.dart';
import 'package:thermoguia_backend/api/mobility_api.dart';
import 'package:thermoguia_backend/api/public_api.dart';
import 'package:thermoguia_backend/api/rewards_api.dart';
import 'package:thermoguia_backend/api/safety_api.dart';
import 'package:thermoguia_backend/api/social_auth_api.dart';
import 'package:thermoguia_backend/api/social_api.dart';
import 'package:thermoguia_backend/app_deps.dart';
import 'package:thermoguia_backend/http/http_utils.dart';
import 'package:thermoguia_backend/http/middleware.dart';

Future<void> main() async {
  final deps = await AppDeps.create();

  final router = Router(notFoundHandler: (Request _) => jsonResponse({'error': 'Rota não encontrada.'}, status: 404));
  registerPublicRoutes(router, deps);
  registerAccountRoutes(router, deps);
  registerSocialAuthRoutes(router, deps);
  registerMobilityRoutes(router, deps);
  registerSafetyRoutes(router, deps);
  registerGuardianRoutes(router, deps);
  registerAssistantRoutes(router, deps);
  registerRewardsRoutes(router, deps);
  registerSocialRoutes(router, deps);
  registerAdminRoutes(router, deps);

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(cors())
      .addMiddleware(errorHandler())
      .addMiddleware(authGuard(deps.auth))
      .addHandler(router.call);

  final server = await io.serve(handler, InternetAddress.anyIPv4, deps.config.port);
  stdout.writeln('ThermoGuia API em http://${server.address.host}:${server.port}');
  stdout.writeln('IA: ${deps.claude.enabled ? 'Claude (${deps.config.anthropicModel})' : 'motor de regras (sem ANTHROPIC_API_KEY)'}');

  // Índices verdes carregam em segundo plano; a API já responde.
  for (final g in deps.green.values) {
    g.init();
  }

  ProcessSignal.sigint.watch().listen((_) async {
    await server.close();
    await deps.db.close();
    exit(0);
  });
}
