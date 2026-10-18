import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../../core/providers.dart';
import '../../../core/services/location_service.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/common.dart';
import 'persona_picker.dart';
import 'session_controller.dart';
import '../../../core/widgets/thermo_loader.dart';

/// Duas etapas: quem é você e quais permissões o app usa (e por quê).
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _name = TextEditingController();
  Persona _persona = Persona.pedestre;
  int _step = 0;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    setState(() => _busy = true);
    // Permissões são opcionais: se o pedido falhar ou for negado, o app segue
    // com a localização padrão e sem lembretes, em vez de travar o cadastro.
    var location = LocationStatus.denied;
    try {
      location = await ref.read(locationServiceProvider).ensurePermission();
    } catch (_) {}
    var notifications = true;
    try {
      await ref.read(notificationServiceProvider).requestPermission();
    } catch (_) {
      notifications = false;
    }
    try {
      final audit = ref.read(auditLoggerProvider);
      await ref.read(sessionProvider).startAnonymous(_name.text.trim(), _persona);
      await audit.log('consentimento_inicial', approved: true, details: {
        'localizacao': location == LocationStatus.ok,
        'notificacoes': notifications,
        'perfil': _persona.name,
      });
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      // A ilustração vai até o topo da tela, por trás da barra de status e do Voltar.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        // O céu da ilustração é claro: ícones escuros na barra de status.
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Voltar',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.85),
              foregroundColor: Tokens.tinta,
            ),
            onPressed: () => _step == 0 ? context.go('/boas-vindas') : setState(() => _step = 0),
          ),
        ),
      ),
      body: ListView(
        padding: EdgeInsets.only(bottom: 24 + MediaQuery.paddingOf(context).bottom),
        children: [
          const _Header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _step == 0 ? _profileStep(t) : _permissionsStep(t),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _profileStep(TextTheme t) => [
        Text('Como podemos te chamar?', style: t.headlineSmall),
        const SizedBox(height: 16),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Seu nome (opcional)'),
        ),
        const SizedBox(height: 32),
        Text('Como você costuma andar pela cidade?', style: t.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Cada perfil muda o cálculo de risco, a meta de água e os alertas. Toque em um para ver.',
          style: t.bodyMedium,
        ),
        const SizedBox(height: 16),
        PersonaPicker(value: _persona, showBenefits: true, onChanged: (p) => setState(() => _persona = p)),
        const SizedBox(height: 40),
        FilledButton(onPressed: () => setState(() => _step = 1), child: const Text('Continuar')),
      ];

  List<Widget> _permissionsStep(TextTheme t) => [
        Text('O que o ThermoGuia vai usar', style: t.headlineSmall),
        const SizedBox(height: 24),
        const _Permission(
          icon: Icons.my_location,
          title: 'Sua localização',
          text: 'Para medir o calor onde você está e montar Rotas Frescas. '
              'Só é usada com o app aberto.',
        ),
        const _Permission(
          icon: Icons.notifications_active_outlined,
          title: 'Notificações',
          text: 'Para lembrar de beber água e avisar quando o calor ficar perigoso.',
        ),
        const _Permission(
          icon: Icons.verified_user_outlined,
          title: 'Você no controle',
          text: 'Nada é enviado a familiares ou serviços de emergência sem a sua confirmação. '
              'Cada decisão fica registrada no seu histórico.',
        ),
        const SizedBox(height: 32),
        FilledButton(
          onPressed: _busy ? null : _finish,
          child: _busy
              ? const ThermoLoader.inline()
              : const Text('Permitir e começar'),
        ),
      ];
}

/// Ilustração de Manaus (rio, ponte, Teatro Amazonas e a folha-rota) no topo.
class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) => const AspectRatio(
        aspectRatio: 1170 / 780,
        child: Image(
          image: AssetImage('assets/illustrations/signup_header.png'),
          fit: BoxFit.cover,
          excludeFromSemantics: true,
        ),
      );
}

class _Permission extends StatelessWidget {
  const _Permission({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 28, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(text, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      );
}
