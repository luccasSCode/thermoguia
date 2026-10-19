import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/assistant/assistant_screen.dart';
import '../../features/community/community_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../features/profile/premium_screen.dart';
import '../../features/rewards/club_screen.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/profile/settings_screen.dart';
import '../../features/routes/presentation/map_screen.dart';
import '../../features/safety/audit_screen.dart';
import '../../features/safety/contacts_screen.dart';
import '../../features/session/presentation/session_controller.dart';
import '../../features/session/presentation/sign_in_screen.dart';
import '../../features/session/presentation/onboarding_screen.dart';
import '../../features/session/presentation/welcome_screen.dart';
import '../widgets/home_shell.dart';
import '../widgets/thermo_loader.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final session = ref.read(sessionProvider);
  const publicPaths = {'/boas-vindas', '/comecar', '/entrar'};

  return GoRouter(
    initialLocation: '/agora',
    refreshListenable: session,
    redirect: (context, state) {
      final path = state.matchedLocation;
      switch (session.status) {
        case SessionStatus.loading:
          return path == '/carregando' ? null : '/carregando';
        case SessionStatus.signedOut:
          return publicPaths.contains(path) ? null : '/boas-vindas';
        case SessionStatus.signedIn:
          return (publicPaths.contains(path) || path == '/carregando') ? '/agora' : null;
      }
    },
    routes: [
      GoRoute(path: '/carregando', builder: (_, __) => const _Loading()),
      GoRoute(path: '/boas-vindas', builder: (_, __) => const WelcomeScreen()),
      GoRoute(path: '/comecar', builder: (_, __) => const OnboardingScreen()),
      GoRoute(path: '/entrar', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/contatos', builder: (_, __) => const ContactsScreen()),
      GoRoute(path: '/historico', builder: (_, __) => const AuditScreen()),
      GoRoute(path: '/planos', builder: (_, __) => const PremiumScreen()),
      GoRoute(path: '/clube', builder: (_, __) => const ClubScreen()),
      GoRoute(path: '/configuracoes', builder: (_, __) => const SettingsScreen()),
      GoRoute(path: '/notificacoes', builder: (_, __) => const NotificationsScreen()),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/agora', builder: (_, __) => const HomeScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/rotas', builder: (_, __) => const MapScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/comunidade', builder: (_, __) => const CommunityScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/assistente', builder: (_, __) => const AssistantScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/perfil', builder: (_, __) => const ProfileScreen())]),
        ],
      ),
    ],
  );
});

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Scaffold(
        body: Center(child: ThermoLoader(size: 180)),
      );
}
