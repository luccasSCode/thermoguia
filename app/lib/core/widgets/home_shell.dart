import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/climate/climate_providers.dart';
import '../../features/notifications/engagement.dart';
import '../../features/rewards/rewards_controller.dart';
import '../providers.dart';

/// Moldura com as abas. Também cuida do que acontece "ao abrir o app":
/// check-in do Clube H2O, agenda de notificações e o toque numa notificação.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> with WidgetsBindingObserver {
  static const _tabs = ['/agora', '/rotas', '/comunidade', '/assistente', '/perfil'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final notifications = ref.read(notificationServiceProvider);
    notifications.onTap = _open;
    Future.microtask(() async {
      final route = await notifications.launchRoute();
      if (route != null && mounted) _open(route);
      await _onOpen();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onOpen();
  }

  Future<void> _onOpen() async {
    await ref.read(rewardsProvider.notifier).checkIn();
    await ref.read(engagementSchedulerProvider)();
  }

  void _open(String route) {
    if (!mounted) return;
    final tab = _tabs.indexOf(route);
    if (tab >= 0) {
      widget.shell.goBranch(tab);
    } else {
      context.push(route);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Previsão nova = textos novos nas notificações da semana.
    ref.listen(climateProvider.select((c) => c.valueOrNull?.fetchedAt), (_, __) {
      ref.read(engagementSchedulerProvider)();
    });
    ref.listen(rewardEventProvider, (_, e) {
      if (e == null) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.water_drop, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('+${e.points} gotas · ${e.title}')),
          ]),
          action: SnackBarAction(label: 'Ver', onPressed: () => context.push('/clube')),
        ));
    });

    final shell = widget.shell;
    return Scaffold(
      body: shell,
      bottomNavigationBar: _FittedLabels(
        labels: _destinations.map((t) => t.label),
        child: NavigationBar(
          selectedIndex: shell.currentIndex,
          onDestinationSelected: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
          destinations: _destinations,
        ),
      ),
    );
  }
}

const _destinations = [
  NavigationDestination(icon: Icon(Icons.thermostat_outlined), selectedIcon: Icon(Icons.thermostat), label: 'Agora'),
  NavigationDestination(icon: Icon(Icons.alt_route_outlined), selectedIcon: Icon(Icons.alt_route), label: 'Rotas'),
  NavigationDestination(icon: Icon(Icons.groups_outlined), selectedIcon: Icon(Icons.groups), label: 'Social', tooltip: 'Comunidade'),
  NavigationDestination(icon: Icon(Icons.forum_outlined), selectedIcon: Icon(Icons.forum), label: 'Assistente'),
  NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Perfil'),
];

/// Com fonte grande (modo Sol ou acessibilidade), reduz a escala do texto só na
/// barra de abas até o rótulo mais longo caber numa linha, sem quebrar a palavra.
class _FittedLabels extends StatelessWidget {
  const _FittedLabels({required this.labels, required this.child});
  final Iterable<String> labels;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final style = NavigationBarTheme.of(context).labelTextStyle?.resolve({WidgetState.selected});
    final itemWidth = mq.size.width / labels.length - 8; // folga lateral de cada aba
    var widest = 0.0;
    for (final label in labels) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      if (painter.width > widest) widest = painter.width;
    }
    final current = mq.textScaler.scale(1);
    final fit = widest == 0 ? current : itemWidth / widest;
    if (current <= fit) return child;
    return MediaQuery(data: mq.copyWith(textScaler: TextScaler.linear(fit.clamp(0.8, current))), child: child);
  }
}
