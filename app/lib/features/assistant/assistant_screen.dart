import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/tokens.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/thermo_loader.dart';
import 'assistant_controller.dart';
import 'assistant_suggestions.dart';

class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();

  /// Muda a cada toque em "Outras ideias" e a cada resposta, para variar as sugestões.
  int _seed = 0;

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _close() {
    final ctrl = ref.read(assistantProvider.notifier);
    final id = ref.read(assistantProvider).conversationId;
    ctrl.close();
    if (id == null) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: const Text('Conversa guardada no histórico.'),
        // Com ação, o SnackBar fica na tela até ser fechado; aqui some sozinho.
        persist: false,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(label: 'Reabrir', onPressed: () => ctrl.open(id)),
      ));
  }

  void _newConversation() {
    ref.read(assistantProvider.notifier).newConversation();
    setState(() => _seed++);
  }

  void _send(String text) {
    _input.clear();
    setState(() => _seed++);
    ref.read(assistantProvider.notifier).send(text);
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(assistantProvider);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final ctx = ref.watch(suggestionContextProvider);
    final asked = {for (final m in s.messages) if (m.role == 'user') m.text};

    ref.listen(assistantProvider.select((x) => x.messages.length), (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
        }
      });
    });

    return Scaffold(
      appBar: AppBar(
        leading: s.isOpen
            ? IconButton(tooltip: 'Fechar conversa', icon: const Icon(Icons.close), onPressed: _close)
            : null,
        title: Text(
          s.isOpen ? (s.history.where((c) => c.id == s.conversationId).firstOrNull?.title ?? 'Assistente') : 'Assistente',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (s.history.isNotEmpty)
            IconButton(
              tooltip: 'Histórico de conversas',
              icon: const Icon(Icons.history),
              onPressed: () => showConversationHistory(context),
            ),
          if (s.isOpen)
            IconButton(
              tooltip: 'Nova conversa',
              icon: const Icon(Icons.add_comment_outlined),
              onPressed: _newConversation,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: s.messages.isEmpty
                ? ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Pergunte sobre o calor de agora', style: t.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                        'Eu uso o clima do seu local, seu perfil, a água que você já bebeu e o tempo ao sol de hoje.',
                        style: t.bodyLarge,
                      ),
                      const SizedBox(height: 20),
                      _SuggestionGrid(
                        items: pickSuggestions(ctx, count: 6, seed: _seed),
                        onTap: (q) => _send(q),
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.autorenew),
                          label: const Text('Outras ideias'),
                          onPressed: () => setState(() => _seed++),
                        ),
                      ),
                      if (s.history.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(children: [
                          Expanded(child: Text('Conversas anteriores', style: t.titleMedium)),
                          if (s.history.length > 3)
                            TextButton(
                              onPressed: () => showConversationHistory(context),
                              child: Text('Ver todas (${s.history.length})'),
                            ),
                        ]),
                        for (final c in s.history.take(3))
                          _ConversationTile(
                            conversation: c,
                            onTap: () => ref.read(assistantProvider.notifier).open(c.id),
                          ),
                      ],
                    ],
                  )
                : ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: s.messages.length + (s.sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i == s.messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: ThermoLoader.inline(),
                          ),
                        );
                      }
                      final m = s.messages[i];
                      final mine = m.role == 'user';
                      return Align(
                        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                        child: Container(
                          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          decoration: BoxDecoration(
                            color: m.isError
                                ? scheme.errorContainer
                                : mine
                                    ? scheme.primary
                                    : scheme.surface,
                            borderRadius: BorderRadius.circular(18).copyWith(
                              bottomRight: mine ? const Radius.circular(4) : null,
                              bottomLeft: mine ? null : const Radius.circular(4),
                            ),
                          ),
                          child: Text(
                            m.text,
                            style: t.bodyLarge?.copyWith(color: mine ? scheme.onPrimary : scheme.onSurface),
                          ),
                        ),
                      );
                    },
                  ),
          ),
          if (s.messages.isNotEmpty && !s.sending && s.remaining != 0)
            _FollowUps(
              items: pickSuggestions(ctx, count: 4, seed: _seed, skip: asked),
              onTap: (q) => _send(q),
            ),
          if (s.remaining == 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: () => context.push('/planos'),
                child: const Text('Conhecer o ThermoGuia+ (assistente sem limite)'),
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: _send,
                    decoration: const InputDecoration(hintText: 'Escreva sua pergunta'),
                  ),
                ),
                IconButton.filled(
                  tooltip: 'Enviar',
                  icon: const Icon(Icons.arrow_upward),
                  onPressed: s.sending ? null : () => _send(_input.text),
                ),
              ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              s.remaining == null ? 'Respostas geradas por IA podem conter erros.' : 'Perguntas restantes hoje: ${s.remaining}',
              style: t.bodySmall?.copyWith(color: Tokens.pedra),
            ),
          ),
        ],
      ),
    );
  }
}

/// Perguntas prontas da primeira tela, em duas colunas.
class _SuggestionGrid extends StatelessWidget {
  const _SuggestionGrid({required this.items, required this.onTap});
  final List<Suggestion> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(builder: (context, box) {
      final w = (box.maxWidth - 10) / 2;
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final s in items)
            SizedBox(
              width: w,
              child: Material(
                color: scheme.surface,
                borderRadius: BorderRadius.circular(Tokens.radiusControl),
                child: InkWell(
                  borderRadius: BorderRadius.circular(Tokens.radiusControl),
                  onTap: () => onTap(s.text),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 108),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Tokens.radiusControl),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(s.icon, color: scheme.primary),
                        const SizedBox(height: 10),
                        Text(s.text, style: t.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }
}

/// Próximas perguntas sugeridas durante a conversa.
class _FollowUps extends StatelessWidget {
  const _FollowUps({required this.items, required this.onTap});
  final List<Suggestion> items;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 48,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          itemCount: items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => ActionChip(
            avatar: Icon(items[i].icon, size: 18),
            label: Text(items[i].text),
            onPressed: () => onTap(items[i].text),
          ),
        ),
      );
}

String _when(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(t.year, t.month, t.day);
  final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  if (day == today) return 'Hoje, $hm';
  if (day == today.subtract(const Duration(days: 1))) return 'Ontem, $hm';
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}';
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.conversation, required this.onTap, this.onDelete});
  final Conversation conversation;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        backgroundColor: Tokens.rio.withValues(alpha: 0.12),
        child: const Icon(Icons.chat_bubble_outline, color: Tokens.rio, size: 20),
      ),
      title: Text(conversation.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.titleSmall),
      subtitle: Text(
        '${_when(conversation.updatedAt)} · ${conversation.preview}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: onDelete == null
          ? const Icon(Icons.chevron_right)
          : IconButton(tooltip: 'Apagar conversa', icon: const Icon(Icons.delete_outline), onPressed: onDelete),
      onTap: onTap,
    );
  }
}

/// Histórico completo: reabrir, apagar uma ou apagar todas.
Future<void> showConversationHistory(BuildContext context) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Consumer(builder: (ctx, ref, _) {
          final history = ref.watch(assistantProvider.select((s) => s.history));
          final ctrl = ref.read(assistantProvider.notifier);
          final t = Theme.of(ctx).textTheme;
          return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 4),
              child: Row(children: [
                Expanded(child: Text('Histórico de conversas', style: t.titleLarge)),
                if (history.isNotEmpty)
                  TextButton(
                    onPressed: () async {
                      final ok = await showDialog<bool>(
                        context: ctx,
                        builder: (d) => AlertDialog(
                          title: const Text('Apagar todas as conversas?'),
                          content: const Text('Isso não pode ser desfeito.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Cancelar')),
                            FilledButton(onPressed: () => Navigator.pop(d, true), child: const Text('Apagar')),
                          ],
                        ),
                      );
                      if (ok == true) await ctrl.clearHistory();
                    },
                    child: const Text('Apagar todas'),
                  ),
              ]),
            ),
            Expanded(
              child: history.isEmpty
                  ? Center(child: Text('Nenhuma conversa guardada.', style: t.bodyLarge))
                  : ListView.builder(
                      controller: scroll,
                      padding: const EdgeInsets.fromLTRB(20, 0, 12, 24),
                      itemCount: history.length,
                      itemBuilder: (_, i) {
                        final c = history[i];
                        return Dismissible(
                          key: ValueKey(c.id),
                          direction: DismissDirection.endToStart,
                          background: Container(
                            alignment: Alignment.centerRight,
                            padding: const EdgeInsets.only(right: 16),
                            color: Theme.of(ctx).colorScheme.errorContainer,
                            child: const Icon(Icons.delete_outline),
                          ),
                          onDismissed: (_) => ctrl.delete(c.id),
                          child: _ConversationTile(
                            conversation: c,
                            onTap: () {
                              ctrl.open(c.id);
                              Navigator.pop(ctx);
                            },
                            onDelete: () {
                              ctrl.delete(c.id);
                              showMessage(context, 'Conversa apagada.');
                            },
                          ),
                        );
                      },
                    ),
            ),
          ]);
        }),
      ),
    );

