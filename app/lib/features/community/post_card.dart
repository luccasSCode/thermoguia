import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/thermo_loader.dart';
import '../session/presentation/session_controller.dart';
import 'community_controller.dart';

String timeAgo(Object? iso) {
  final t = DateTime.tryParse('$iso')?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'agora';
  if (d.inMinutes < 60) return 'há ${d.inMinutes} min';
  if (d.inHours < 24) return 'há ${d.inHours} h';
  if (d.inDays < 7) return 'há ${d.inDays} ${d.inDays == 1 ? 'dia' : 'dias'}';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
}

class PersonAvatar extends ConsumerWidget {
  const PersonAvatar({super.key, required this.userId, required this.version, required this.name, this.radius = 20});
  final String userId;
  final String? version;
  final String name;
  final double radius;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photo = ref.watch(userAvatarProvider((userId, version))).valueOrNull;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Tokens.rio.withValues(alpha: 0.15),
      foregroundImage: photo == null ? null : MemoryImage(photo),
      child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(color: Tokens.rio, fontWeight: FontWeight.w700, fontSize: radius * 0.8)),
    );
  }
}

class PostPhoto extends ConsumerWidget {
  const PostPhoto({super.key, required this.postId, required this.kind, this.label});
  final String postId;
  final String kind;
  final String? label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final img = ref.watch(postImageProvider((postId, kind)));
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(fit: StackFit.expand, children: [
        Container(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          child: img.when(
            data: (b) => Image.memory(b, fit: BoxFit.cover, gaplessPlayback: true),
            loading: () => const Center(child: ThermoLoader.inline(size: 28)),
            error: (_, __) => const Center(child: Icon(Icons.broken_image_outlined)),
          ),
        ),
        if (label != null)
          Positioned(
            left: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
              child:
                  Text(label!, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}

/// Selo verde de verificação (IA ou equipe).
class VerifiedChip extends StatelessWidget {
  const VerifiedChip({super.key, required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final by = post['verifiedBy'] == 'revisao' ? 'pela equipe' : 'pela IA';
    return Tooltip(
      message: 'Comprovado $by',
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.verified, color: Tokens.copa, size: 18),
        const SizedBox(width: 4),
        Text('Verificado', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Tokens.copa)),
      ]),
    );
  }
}

class PostCard extends ConsumerStatefulWidget {
  const PostCard({super.key, required this.post, this.showStatus = false});
  final Post post;

  /// Em "Minhas", mostra a situação da verificação em vez das reações.
  final bool showStatus;

  @override
  ConsumerState<PostCard> createState() => _PostCardState();
}

class _PostCardState extends ConsumerState<PostCard> {
  late Post p = widget.post;
  bool _busy = false;

  @override
  void didUpdateWidget(PostCard old) {
    super.didUpdateWidget(old);
    if (old.post != widget.post) p = widget.post;
  }

  Future<void> _react(String kind) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fresh = await ref.read(communityActionsProvider).react(p, kind);
      if (mounted) setState(() => p = fresh);
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _menu(String action) async {
    final actions = ref.read(communityActionsProvider);
    try {
      switch (action) {
        case 'excluir':
          final ok = await _confirm('Excluir publicação?', 'As gotas já ganhas continuam com você.');
          if (ok) {
            await actions.delete(p['id'] as String);
            if (mounted) showMessage(context, 'Publicação excluída.');
          }
        case 'denunciar':
          final reason = await _askReason();
          if (reason != null) {
            await actions.report('post', p['id'] as String, reason);
            if (mounted) showMessage(context, 'Obrigado. A equipe vai analisar.');
          }
        case 'bloquear':
          final ok = await _confirm(
              'Bloquear ${p['author']}?', 'Vocês deixam de ver as publicações e comentários um do outro.');
          if (ok) {
            await actions.block(p['userId'] as String);
            if (mounted) showMessage(context, '${p['author']} foi bloqueado(a).');
          }
      }
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    }
  }

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Confirmar')),
          ],
        ),
      ) ??
      false;

  Future<String?> _askReason() => showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const ListTile(title: Text('Por que denunciar?')),
            for (final r in const [
              'A foto não comprova o que diz',
              'Foto repetida ou tirada da internet',
              'Conteúdo impróprio ou ofensivo',
              'Expõe dados pessoais de alguém',
            ])
              ListTile(title: Text(r), onTap: () => Navigator.pop(ctx, r)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final me = ref.watch(sessionProvider.select((s) => s.user?.id));
    final mine = p['userId'] == me;
    final cat = categoryOf(p['category'] as String);
    final images = (p['images'] as List).cast<String>();
    final badges = (p['authorBadges'] as List? ?? const []).cast<String>();
    final ml = p['verifiedMl'] as int?;
    final status = p['status'] as String;
    final byKind = (p['byKind'] as Map? ?? const {}).cast<String, dynamic>();

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 8),
          child: Row(children: [
            PersonAvatar(
                userId: p['userId'] as String, version: p['authorAvatar'] as String?, name: p['author'] as String),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['author'] as String, style: t.titleSmall),
                if (badges.isNotEmpty)
                  Wrap(spacing: 4, runSpacing: 2, children: [for (final b in badges) _BadgeTag(text: b)]),
                Text('${cat.label} · ${timeAgo(p['createdAt'])}', style: t.bodySmall),
              ]),
            ),
            PopupMenuButton<String>(
              tooltip: 'Mais opções',
              onSelected: _menu,
              itemBuilder: (_) => [
                if (mine) const PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                if (!mine) const PopupMenuItem(value: 'denunciar', child: Text('Denunciar')),
                if (!mine) const PopupMenuItem(value: 'bloquear', child: Text('Bloquear pessoa')),
              ],
            ),
          ]),
        ),
        if (images.length == 2)
          Row(children: [
            Expanded(child: PostPhoto(postId: p['id'] as String, kind: 'antes', label: 'Antes')),
            const SizedBox(width: 2),
            Expanded(
              child: status == 'aguardando_depois'
                  ? AspectRatio(
                      aspectRatio: 1,
                      child: Container(
                        color: scheme.surfaceContainerHighest,
                        alignment: Alignment.center,
                        child: const Text('Falta a foto\n"depois"', textAlign: TextAlign.center),
                      ),
                    )
                  : PostPhoto(postId: p['id'] as String, kind: 'depois', label: 'Depois'),
            ),
          ])
        else
          PostPhoto(postId: p['id'] as String, kind: 'foto'),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (status == 'aprovado')
              Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                VerifiedChip(post: p),
                if (ml != null)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.water_drop, size: 18, color: Tokens.rio),
                    Text(
                        ' ${ml >= 1000 ? '${(ml / 1000).toStringAsFixed(1).replaceAll('.', ',')} L' : '$ml ml'} comprovados',
                        style: t.labelMedium?.copyWith(color: Tokens.rio)),
                  ]),
              ]),
            if (widget.showStatus && status != 'aprovado') _StatusLine(post: p),
            if ('${p['caption'] ?? ''}'.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('${p['caption']}', style: t.bodyMedium),
            ],
          ]),
        ),
        if (status == 'aprovado')
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Quebra em duas linhas em telas estreitas ou com letra grande.
              Expanded(
                child: Wrap(spacing: 4, runSpacing: 0, children: [
                  for (final (kind, emoji, label) in reactionKinds)
                    Semantics(
                      button: true,
                      selected: p['myReaction'] == kind,
                      label: '$label, ${byKind[kind] ?? 0}',
                      child: ChoiceChip(
                        visualDensity: VisualDensity.compact,
                        showCheckmark: false,
                        label: Text('$emoji ${byKind[kind] ?? 0}'),
                        selected: p['myReaction'] == kind,
                        onSelected: (_) => _react(kind),
                      ),
                    ),
                ]),
              ),
              TextButton.icon(
                icon: const Icon(Icons.mode_comment_outlined, size: 20),
                label: Text('${p['comments']}'),
                onPressed: () => showComments(context, p),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _BadgeTag extends StatelessWidget {
  const _BadgeTag({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(color: Tokens.sol.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(20)),
        child: Text('🏅 $text', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700)),
      );
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.post});
  final Post post;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final (IconData icon, Color color, String title) = switch (post['status']) {
      'verificando' => (Icons.hourglass_top, Tokens.rio, 'Verificando a foto…'),
      'revisao' => (Icons.manage_search, Tokens.sol, 'Em revisão pela equipe'),
      'aguardando_depois' => (Icons.timer_outlined, Tokens.rio, 'Esperando a foto "depois"'),
      'recusado' => (Icons.block, Theme.of(context).colorScheme.error, 'Não comprovado'),
      _ => (Icons.info_outline, Tokens.pedra, '${post['status']}'),
    };
    final reason = '${post['reason'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.titleSmall?.copyWith(color: color)),
            if (reason.isNotEmpty && post['status'] != 'verificando') Text(reason, style: t.bodySmall),
          ]),
        ),
      ]),
    );
  }
}

/// Comentários de um post.
Future<void> showComments(BuildContext context, Post post) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: SizedBox(height: MediaQuery.of(ctx).size.height * 0.7, child: _Comments(post: post)),
      ),
    );

final _commentsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((ref, id) async {
  final list = await ref.read(apiClientProvider).get('/social/posts/$id/comments') as List;
  return list.map((e) => (e as Map).cast<String, dynamic>()).toList();
});

class _Comments extends ConsumerStatefulWidget {
  const _Comments({required this.post});
  final Post post;

  @override
  ConsumerState<_Comments> createState() => _CommentsState();
}

class _CommentsState extends ConsumerState<_Comments> {
  final _text = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  String get _id => widget.post['id'] as String;

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      await ref.read(apiClientProvider).post('/social/posts/$_id/comments', {'text': text});
      _text.clear();
      ref.invalidate(_commentsProvider(_id));
      ref.read(feedProvider.notifier).refresh();
    } catch (e) {
      if (mounted) showMessage(context, errorText(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_commentsProvider(_id));
    final me = ref.watch(sessionProvider.select((s) => s.user?.id));
    final t = Theme.of(context).textTheme;
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        child: Row(children: [Text('Comentários', style: t.titleLarge)]),
      ),
      Expanded(
        child: list.when(
          loading: () => const Center(child: ThermoLoader(size: 64)),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_commentsProvider(_id))),
          data: (items) => items.isEmpty
              ? Center(child: Text('Seja a primeira pessoa a comentar.', style: t.bodyLarge))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: items.length,
                  itemBuilder: (_, i) {
                    final c = items[i];
                    final mine = c['userId'] == me;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: PersonAvatar(
                          userId: c['userId'] as String,
                          version: c['authorAvatar'] as String?,
                          name: c['author'] as String,
                          radius: 16),
                      title: Text('${c['author']} · ${timeAgo(c['createdAt'])}', style: t.labelMedium),
                      subtitle: Text(c['text'] as String, style: t.bodyMedium),
                      trailing: IconButton(
                        tooltip: mine ? 'Apagar comentário' : 'Denunciar comentário',
                        icon: Icon(mine ? Icons.delete_outline : Icons.flag_outlined, size: 20),
                        onPressed: () async {
                          try {
                            if (mine) {
                              await ref.read(apiClientProvider).delete('/social/comments/${c['id']}');
                            } else {
                              await ref.read(communityActionsProvider).report('comentario', c['id'] as String, '');
                              if (context.mounted) showMessage(context, 'Obrigado. A equipe vai analisar.');
                            }
                            ref.invalidate(_commentsProvider(_id));
                          } catch (e) {
                            if (context.mounted) showMessage(context, errorText(e));
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
      ),
      SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(children: [
            Expanded(
              child: TextField(
                controller: _text,
                maxLength: 500,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'Escreva um comentário', counterText: ''),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton.filled(
              tooltip: 'Enviar',
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ]),
        ),
      ),
    ]);
  }
}
