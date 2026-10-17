import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/thermo_loader.dart';
import 'community_controller.dart';
import 'post_card.dart';

/// Comunidade: fotos que comprovam hábitos contra o calor, verificadas pela
/// IA antes de aparecer, com reações, comentários e selos da semana.
class CommunityScreen extends ConsumerStatefulWidget {
  const CommunityScreen({super.key});

  @override
  ConsumerState<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends ConsumerState<CommunityScreen> with SingleTickerProviderStateMixin {
  late final _tabs = TabController(length: 3, vsync: this);

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Comunidade'),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.water_drop_outlined),
              label: const Text('Clube H2O'),
              onPressed: () => context.push('/clube'),
            ),
          ],
          bottom: TabBar(controller: _tabs, tabs: const [
            Tab(text: 'Feed'),
            Tab(text: 'Destaques'),
            Tab(text: 'Minhas'),
          ]),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () async {
            final posted = await startPublish(context, ref);
            if (posted) _tabs.animateTo(2);
          },
          icon: const Icon(Icons.add_a_photo_outlined),
          label: const Text('Comprovar'),
        ),
        body: TabBarView(controller: _tabs, children: const [_Feed(), _Highlights(), _Mine()]),
      );
}

class _Feed extends ConsumerWidget {
  const _Feed();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(feedProvider);
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () => ref.read(feedProvider.notifier).refresh(),
      child: feed.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: ThermoLoader()),
        error: (e, _) => ListView(children: [ErrorView(error: e, onRetry: () => ref.read(feedProvider.notifier).refresh())]),
        data: (posts) => posts.isEmpty
            ? ListView(padding: const EdgeInsets.all(24), children: [
                const Icon(Icons.groups_outlined, size: 56, color: Tokens.rio),
                const SizedBox(height: 12),
                Text('Ainda não há publicações verificadas.', style: t.titleMedium, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('Comprove que bebeu água ou se protegeu do sol e ganhe gotas no Clube H2O.',
                    style: t.bodyMedium, textAlign: TextAlign.center),
              ])
            : NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  if (n.metrics.extentAfter < 600) ref.read(feedProvider.notifier).loadMore();
                  return false;
                },
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
                  itemCount: posts.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) => i == 0 ? const _HowItWorks() : PostCard(post: posts[i - 1]),
                ),
              ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Tokens.copa.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(Tokens.radiusControl),
        ),
        child: Row(children: [
          const Icon(Icons.verified, color: Tokens.copa),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Toda foto aqui foi verificada pela IA ou pela equipe antes de aparecer. '
              'Quem recebe mais reações e comentários na semana ganha um selo.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ]),
      );
}

/// Selos em vigor (vencedores da semana passada) e a disputa desta semana.
class _Highlights extends ConsumerWidget {
  const _Highlights();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(badgesProvider);
    final t = Theme.of(context).textTheme;
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(badgesProvider),
      child: data.when(
        loading: () => const Center(child: ThermoLoader()),
        error: (e, _) => ListView(children: [ErrorView(error: e, onRetry: () => ref.invalidate(badgesProvider))]),
        data: (d) {
          final holders = (d['holders'] as List).cast<Map>();
          final race = (d['race'] as List).cast<Map>();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
            Text('Selos desta semana', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Ganhos pelas publicações verificadas com mais reações e comentários na semana passada.',
                style: t.bodySmall),
            const SizedBox(height: 10),
            if (holders.isEmpty)
              Text('Nenhum selo foi conquistado na semana passada.', style: t.bodyMedium)
            else
              for (final h in holders)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: PersonAvatar(
                      userId: h['userId'] as String, version: h['avatarUpdatedAt'] as String?, name: h['name'] as String),
                  title: Text('🏅 ${h['badge']}', style: t.titleSmall),
                  subtitle: Text('${h['name']} · ${h['score']} pontos de interação'),
                ),
            const SizedBox(height: 20),
            Text('Disputa da semana', style: t.titleLarge),
            const SizedBox(height: 4),
            Text('Reação vale 1 ponto, comentário vale 2. O selo fecha no domingo e rende +50 gotas.', style: t.bodySmall),
            for (final c in race) _RaceCard(category: c.cast<String, dynamic>()),
          ]);
        },
      ),
    );
  }
}

class _RaceCard extends StatelessWidget {
  const _RaceCard({required this.category});
  final Map<String, dynamic> category;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final leaders = (category['leaders'] as List).cast<Map>();
    final trips = category['category'] == 'rota_fresca';
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('🏅 ${category['badge']}', style: t.titleSmall),
          if (trips) Text('Quem mais concluiu Rotas Frescas pelo app', style: t.bodySmall),
          const SizedBox(height: 6),
          if (leaders.isEmpty)
            Text('Ninguém pontuou ainda. Pode ser você!', style: t.bodyMedium)
          else
            for (var i = 0; i < leaders.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  SizedBox(width: 22, child: Text('${i + 1}º', style: t.labelLarge)),
                  PersonAvatar(
                    userId: leaders[i]['userId'] as String,
                    version: leaders[i]['avatarUpdatedAt'] as String?,
                    name: leaders[i]['name'] as String,
                    radius: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(leaders[i]['name'] as String, style: t.bodyMedium)),
                  Text('${leaders[i]['score']} ${trips ? 'rotas' : 'pts'}', style: t.labelLarge),
                ]),
              ),
        ]),
      ),
    );
  }
}

/// Minhas publicações: acompanha a verificação e as provas de água em andamento.
class _Mine extends ConsumerStatefulWidget {
  const _Mine();

  @override
  ConsumerState<_Mine> createState() => _MineState();
}

class _MineState extends ConsumerState<_Mine> {
  Timer? _poll;

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  /// Enquanto houver foto "verificando", consulta de novo a cada 5 s.
  void _schedulePoll(List<Post> posts) {
    final waiting = posts.any((p) => p['status'] == 'verificando');
    if (!waiting) {
      _poll?.cancel();
      _poll = null;
      return;
    }
    _poll ??= Timer.periodic(const Duration(seconds: 5), (_) {
      ref.invalidate(myPostsProvider);
      ref.read(communityActionsProvider).refreshRewards();
    });
  }

  @override
  Widget build(BuildContext context) {
    final mine = ref.watch(myPostsProvider);
    final t = Theme.of(context).textTheme;
    ref.listen(myPostsProvider, (prev, next) {
      final before = {for (final p in prev?.valueOrNull ?? const <Post>[]) p['id']: p['status']};
      for (final p in next.valueOrNull ?? const <Post>[]) {
        if (before[p['id']] == 'verificando' && p['status'] != 'verificando') {
          showMessage(context, p['status'] == 'aprovado' ? 'Foto verificada! Gotas na conta.' : 'Sua foto foi analisada.');
          ref.read(feedProvider.notifier).refresh();
        }
      }
    });
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(myPostsProvider),
      child: mine.when(
        skipLoadingOnRefresh: true,
        skipLoadingOnReload: true,
        loading: () => const Center(child: ThermoLoader()),
        error: (e, _) => ListView(children: [ErrorView(error: e, onRetry: () => ref.invalidate(myPostsProvider))]),
        data: (posts) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _schedulePoll(posts));
          if (posts.isEmpty) {
            return ListView(padding: const EdgeInsets.all(24), children: [
              Text('Você ainda não publicou.', style: t.titleMedium, textAlign: TextAlign.center),
              const SizedBox(height: 6),
              Text('Toque em "Comprovar" para enviar sua primeira foto.', style: t.bodyMedium, textAlign: TextAlign.center),
            ]);
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: posts.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) {
              final p = posts[i];
              return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                PostCard(post: p, showStatus: true),
                if (p['status'] == 'aguardando_depois') _WaterAfterButton(post: p),
              ]);
            },
          );
        },
      ),
    );
  }
}

class _WaterAfterButton extends ConsumerWidget {
  const _WaterAfterButton({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: FilledButton.icon(
          icon: const Icon(Icons.photo_camera_outlined),
          label: const Text('Tirar a foto "depois"'),
          onPressed: () => finishWaterFlow(context, ref, post),
        ),
      );
}

// ---------------- publicar ----------------

/// Escolhe a categoria e envia. Devolve true se algo foi enviado.
Future<bool> startPublish(BuildContext context, WidgetRef ref) async {
  if (!await _consent(context, ref)) return false;
  if (!context.mounted) return false;
  final cat = await showModalBottomSheet<CommunityCategory>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(
            title: Text('O que você quer comprovar?', style: Theme.of(ctx).textTheme.titleLarge),
            subtitle: const Text('Tire uma foto ou escolha da galeria. Ela é verificada antes de aparecer.'),
          ),
          for (final c in communityCategories)
            ListTile(
              leading: CircleAvatar(
                backgroundColor: Tokens.rio.withValues(alpha: 0.12),
                child: Icon(c.icon, color: Tokens.rio),
              ),
              title: Text(c.id == 'agua' ? 'Comprovar água (2 fotos)' : c.label),
              subtitle: Text(c.hint),
              isThreeLine: true,
              trailing: const Icon(Icons.add_a_photo_outlined),
              onTap: () => Navigator.pop(ctx, c),
            ),
        ]),
      ),
    ),
  );
  if (cat == null || !context.mounted) return false;
  return cat.id == 'agua' ? _startWater(context, ref) : _publishPhoto(context, ref, cat);
}

/// A foto fica visível para todos: a pessoa aceita uma vez.
Future<bool> _consent(BuildContext context, WidgetRef ref) async {
  final store = ref.read(localStoreProvider);
  if (store.getString('community_consent') == '1') return true;
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Antes de publicar'),
      content: const Text(
        '• Suas fotos aprovadas ficam visíveis para todas as pessoas do ThermoGuia, com seu primeiro nome e sua foto de perfil.\n'
        '• Cada foto é analisada por IA e, se houver dúvida, pela equipe. Fotos repetidas, de tela ou da internet são recusadas.\n'
        '• Não publique documentos, placas de carro nem pessoas que não autorizaram.\n'
        '• Você pode excluir suas publicações quando quiser.',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Agora não')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Entendi e aceito')),
      ],
    ),
  );
  if (ok == true) await store.setString('community_consent', '1');
  return ok == true;
}

Future<Uint8List?> _capture(BuildContext context, WidgetRef ref, String title) async {
  final actions = ref.read(communityActionsProvider);
  final fromGallery = await showModalBottomSheet<bool>(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(title: Text(title)),
        ListTile(
          leading: const Icon(Icons.photo_camera_outlined),
          title: const Text('Tirar foto'),
          onTap: () => Navigator.pop(ctx, false),
        ),
        ListTile(
          leading: const Icon(Icons.photo_library_outlined),
          title: const Text('Escolher da galeria'),
          onTap: () => Navigator.pop(ctx, true),
        ),
      ]),
    ),
  );
  if (fromGallery == null) return null;
  try {
    return await actions.takePhoto(fromGallery: fromGallery);
  } catch (e) {
    if (context.mounted) {
      showMessage(
        context,
        fromGallery
            ? 'Não foi possível abrir a galeria. Confira a permissão nos Ajustes do aparelho.'
            : 'Não foi possível abrir a câmera. Confira a permissão nos Ajustes do aparelho.',
      );
    }
    return null;
  }
}

Future<String?> _askCaption(BuildContext context, Uint8List photo, String title) {
  final text = TextEditingController();
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(Tokens.radiusControl),
              child: Image.memory(photo, height: 220, fit: BoxFit.cover),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: text,
              maxLength: 280,
              decoration: const InputDecoration(labelText: 'Legenda (opcional)'),
            ),
            FilledButton(onPressed: () => Navigator.pop(ctx, text.text.trim()), child: const Text('Enviar para verificação')),
          ]),
        ),
      ),
    ),
  );
}

Future<bool> _publishPhoto(BuildContext context, WidgetRef ref, CommunityCategory c) async {
  final photo = await _capture(context, ref, c.label);
  if (photo == null || !context.mounted) return false;
  final caption = await _askCaption(context, photo, c.label);
  if (caption == null || !context.mounted) return false;
  try {
    await ref.read(communityActionsProvider).publish(c.id, caption, photo);
    if (context.mounted) showMessage(context, 'Enviado! Você recebe as gotas assim que a foto for verificada.');
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
    return false;
  }
}

Future<bool> _startWater(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Comprovar água'),
      content: const Text(
        '1. Agora: foto da garrafa ou copo ANTES de beber, com o rótulo ou as marcações de ml aparecendo.\n'
        '2. Beba a água.\n'
        '3. Depois de pelo menos 10 minutos (até 6 horas): foto do MESMO recipiente, no mesmo ângulo.\n\n'
        'A IA compara as duas fotos e calcula quanto você bebeu. Cada 100 ml vale 1 gota (até 3 litros por dia).',
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
        FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Tirar a foto "antes"')),
      ],
    ),
  );
  if (ok != true || !context.mounted) return false;
  final photo = await _capture(context, ref, 'Foto "antes"');
  if (photo == null || !context.mounted) return false;
  try {
    await ref.read(communityActionsProvider).startWater(photo);
    if (context.mounted) {
      showMessage(context, 'Foto "antes" guardada. Volte em "Minhas" daqui a 10 minutos para a foto "depois".');
    }
    return true;
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
    return false;
  }
}

Future<void> finishWaterFlow(BuildContext context, WidgetRef ref, Post post) async {
  final photo = await _capture(context, ref, 'Foto "depois"');
  if (photo == null || !context.mounted) return;
  final caption = await _askCaption(context, photo, 'Foto "depois"');
  if (caption == null || !context.mounted) return;
  try {
    await ref.read(communityActionsProvider).finishWater(post['id'] as String, caption, photo);
    if (context.mounted) showMessage(context, 'Enviado! A IA está comparando as duas fotos.');
  } catch (e) {
    if (context.mounted) showMessage(context, errorText(e));
  }
}
