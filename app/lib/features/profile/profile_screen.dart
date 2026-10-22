import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:thermo_core/thermo_core.dart';

import '../../core/providers.dart';
import '../../core/theme/theme_mode.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../adaptive/adaptive_controller.dart';
import '../adaptive/sun_mode.dart';
import '../climate/climate_providers.dart';
import '../outdoor/outdoor_session_controller.dart';
import '../safety/guardian.dart';
import 'avatar.dart';
import '../session/presentation/persona_picker.dart';
import '../session/presentation/session_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final user = session.user;
    final profile = ref.watch(adaptiveProvider);
    final sun = ref.watch(sunModeSettingProvider);
    final theme = ref.watch(themeSettingProvider);
    final t = Theme.of(context).textTheme;
    if (user == null) return const SizedBox.shrink();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil'),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.settings_outlined),
            label: const Text('Configurações'),
            onPressed: () => context.push('/configuracoes'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 40),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
            child: Row(children: [
              Semantics(
                button: true,
                label: user.hasAvatar ? 'Trocar foto de perfil' : 'Adicionar foto de perfil',
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => changeAvatar(context, ref),
                  child: Stack(clipBehavior: Clip.none, children: [
                    const UserAvatar(radius: 40),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                        ),
                        child: Icon(
                          user.hasAvatar ? Icons.edit : Icons.add_a_photo_outlined,
                          size: 16,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.name.isEmpty ? 'Sem nome' : user.name, style: t.titleLarge),
                  Text(user.email ?? 'Conta sem e-mail', style: t.bodyMedium),
                  if (!user.hasAvatar)
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      onPressed: () => changeAvatar(context, ref),
                      child: const Text('Adicionar foto'),
                    ),
                ]),
              ),
              IconButton(
                tooltip: 'Editar nome',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _editName(context, ref, user.name),
              ),
            ]),
          ),
          if (user.isAnonymous)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.alternate_email),
                label: const Text('Adicionar e-mail para não perder seus dados'),
                onPressed: () => _addCredentials(context, ref),
              ),
            ),
          if (user.persona == Persona.idoso) const GuardianCard(),
          const _OutdoorMode(),
          const SectionTitle('Como você se desloca'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: PersonaPicker(
              value: user.persona,
              onChanged: (p) async {
                try {
                  await ref.read(sessionProvider).update(persona: p);
                } catch (e) {
                  if (context.mounted) showMessage(context, errorText(e));
                }
              },
            ),
          ),
          const SectionTitle('O que o ThermoGuia aprendeu sobre você'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_sensitivityText(profile), style: t.bodyLarge),
                const SizedBox(height: 8),
                Text(_shadeText(profile), style: t.bodyLarge),
                if (profile.habitualHours.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Você costuma sair às ${profile.habitualHours.map((h) => '${h}h').join(' e ')}.', style: t.bodyLarge),
                ],
                const SizedBox(height: 8),
                Text(
                  'Baseado em ${profile.feedbackCount} respostas após trajetos e ${profile.routeChoices} rotas escolhidas.',
                  style: t.bodySmall,
                ),
                TextButton(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () async {
                    await ref.read(adaptiveProvider.notifier).reset();
                    if (context.mounted) showMessage(context, 'Aprendizado reiniciado.');
                  },
                  child: const Text('Recomeçar aprendizado'),
                ),
              ],
            ),
          ),
          const SectionTitle('Aparência'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<ThemeSetting>(
                    showSelectedIcon: false,
                    segments: [
                      for (final s in ThemeSetting.values) ButtonSegment(value: s, label: _OneLine(s.label)),
                    ],
                    selected: {theme},
                    onSelectionChanged: (v) => ref.read(themeSettingProvider.notifier).set(v.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'O modo escuro descansa a vista à noite. Quando o Modo Sol Forte '
                  'está ligado, a tela fica clara para dar para ler no sol.',
                  style: t.bodyMedium,
                ),
              ],
            ),
          ),
          const SectionTitle('Modo Sol Forte'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<SunModeSetting>(
                    showSelectedIcon: false,
                    segments: [
                      for (final s in SunModeSetting.values) ButtonSegment(value: s, label: _OneLine(s.label)),
                    ],
                    selected: {sun},
                    onSelectionChanged: (v) => ref.read(sunModeSettingProvider.notifier).set(v.first),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Alto contraste e letras maiores para ler a tela sob o sol. '
                  'No automático, liga com UV 7 ou mais e quando você está na rua.',
                  style: t.bodyMedium,
                ),
              ],
            ),
          ),
          const SectionTitle('Segurança'),
          if (user.persona != Persona.idoso) ...[const GuardianCard(), const SizedBox(height: 8)],
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.contact_emergency_outlined),
            title: const Text('Contatos de emergência'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/contatos'),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.volunteer_activism_outlined),
            title: const Text('Apoie o ThermoGuia'),
            subtitle: const Text('Doe e ajude a plantar árvores em Manaus'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/apoiar'),
          ),
          const Divider(height: 32),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: const Icon(Icons.logout),
            title: const Text('Sair'),
            onTap: () => ref.read(sessionProvider).signOut(),
          ),
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Excluir minha conta', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            onTap: () => _delete(context, ref),
          ),
        ],
      ),
    );
  }

  String _sensitivityText(AdaptiveProfile p) {
    final o = p.sensitivityOffset;
    final v = o.abs().toStringAsFixed(1).replaceAll('.', ',');
    if (p.feedbackCount == 0) return 'Responda "Como você se sentiu?" ao final dos trajetos para eu conhecer seu corpo.';
    if (o > 0.4) return 'Você sente o calor mais que a média (+$v °C). Ajustei os alertas para avisar mais cedo.';
    if (o < -0.4) return 'Você tolera bem o calor (−$v °C). Os alertas ficaram menos frequentes.';
    return 'Sua sensação de calor está próxima da média.';
  }

  String _shadeText(AdaptiveProfile p) {
    final pct = (p.shadePreference * 100).round();
    if (p.routeChoices == 0) return 'Nas rotas, começo dando peso de $pct% para a sombra.';
    return p.shadePreference >= 0.6
        ? 'Você costuma aceitar caminhar um pouco mais para ter sombra ($pct% de peso).'
        : 'Você prefere caminhos mais curtos ($pct% de peso para a sombra).';
  }

  Future<void> _editName(BuildContext context, WidgetRef ref, String current) async {
    final c = TextEditingController(text: current);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seu nome'),
        content: TextField(controller: c, autofocus: true, textCapitalization: TextCapitalization.words),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Salvar')),
        ],
      ),
    );
    if (name == null) return;
    try {
      await ref.read(sessionProvider).update(name: name);
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _addCredentials(BuildContext context, WidgetRef ref) async {
    final email = TextEditingController();
    final pass = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Adicionar e-mail'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'E-mail')),
          const SizedBox(height: 12),
          TextField(controller: pass, obscureText: true, decoration: const InputDecoration(labelText: 'Senha (8+ caracteres)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Salvar e-mail')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(sessionProvider).addCredentials(email.text.trim(), pass.text);
      if (context.mounted) showMessage(context, 'E-mail salvo. Agora você pode entrar em outro aparelho.');
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir sua conta?'),
        content: const Text(
          'Seus dados pessoais, trajetos, contatos e aprendizado serão apagados. '
          'O histórico de decisões é mantido sem identificação, como exige a auditoria.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Excluir conta'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(sessionProvider).deleteAccount();
    } catch (e) {
      if (context.mounted) showMessage(context, errorText(e));
    }
  }
}

/// Registra o interesse em doar (e, antes, em planos).
Future<void> logPlanInterest(WidgetRef ref, String plan) =>
    ref.read(auditLoggerProvider).log('interesse_plano', details: {'plano': plan});

/// Rótulo que nunca quebra a palavra: com fonte grande, encolhe para caber.
class _OneLine extends StatelessWidget {
  const _OneLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) =>
      FittedBox(fit: BoxFit.scaleDown, child: Text(text, maxLines: 1, softWrap: false));
}

/// "Estou na rua agora": conta o tempo ao sol e liga os lembretes de água.
class _OutdoorMode extends ConsumerWidget {
  const _OutdoorMode();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(outdoorSessionProvider);
    final risk = ref.watch(riskProvider);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SectionTitle('Na rua'),
      SwitchListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        secondary: Icon(Icons.directions_walk, color: s.active ? Tokens.copa : null),
        value: s.active,
        onChanged: (_) => ref.read(outdoorSessionProvider.notifier).toggle(),
        title: const Text('Estou na rua agora'),
        subtitle: Text(s.active && risk != null
            ? 'Contando seu tempo ao sol. Lembrete de água a cada ${risk.hydrationIntervalMin} min.'
            : 'Hoje: ${s.minutesToday} min ao sol. Ative para receber lembretes de água.'),
      ),
    ]);
  }
}
