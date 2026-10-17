import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_client.dart';
import '../../core/providers.dart';
import '../climate/climate_providers.dart';
import '../hydration/hydration_controller.dart';
import '../outdoor/outdoor_session_controller.dart';

class ChatMessage {
  const ChatMessage(this.role, this.text, {this.isError = false});
  final String role; // user | assistant
  final String text;
  final bool isError;

  Map<String, String> toApi() => {'role': role, 'content': text};

  Map<String, dynamic> toJson() => {'role': role, 'text': text, if (isError) 'error': true};

  factory ChatMessage.fromJson(Map<String, dynamic> j) =>
      ChatMessage(j['role'] as String, j['text'] as String, isError: j['error'] == true);
}

/// Conversa guardada no histórico (no aparelho).
class Conversation {
  const Conversation({required this.id, required this.title, required this.updatedAt, required this.messages});
  final String id;
  final String title;
  final DateTime updatedAt;
  final List<ChatMessage> messages;

  /// Última resposta, para a prévia na lista.
  String get preview => messages.lastWhere((m) => m.role == 'assistant', orElse: () => messages.last).text;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'updatedAt': updatedAt.toIso8601String(),
        'messages': messages.map((m) => m.toJson()).toList(),
      };

  factory Conversation.fromJson(Map<String, dynamic> j) => Conversation(
        id: j['id'] as String,
        title: j['title'] as String,
        updatedAt: DateTime.parse(j['updatedAt'] as String),
        messages: (j['messages'] as List).map((m) => ChatMessage.fromJson((m as Map).cast<String, dynamic>())).toList(),
      );
}

class AssistantState {
  const AssistantState({
    this.messages = const [],
    this.sending = false,
    this.remaining,
    this.conversationId,
    this.history = const [],
  });

  /// Conversa aberta (vazia = tela inicial com sugestões).
  final List<ChatMessage> messages;
  final bool sending;
  final int? remaining;
  final String? conversationId;

  /// Conversas anteriores, da mais recente para a mais antiga.
  final List<Conversation> history;

  bool get isOpen => messages.isNotEmpty;

  AssistantState copyWith({
    List<ChatMessage>? messages,
    bool? sending,
    int? remaining,
    String? conversationId,
    bool clearConversation = false,
    List<Conversation>? history,
  }) =>
      AssistantState(
        messages: messages ?? this.messages,
        sending: sending ?? this.sending,
        remaining: remaining ?? this.remaining,
        conversationId: clearConversation ? null : (conversationId ?? this.conversationId),
        history: history ?? this.history,
      );
}

/// Assistente com histórico de conversas guardado no aparelho (apagado ao
/// sair da conta, junto com os outros dados locais).
class AssistantController extends Notifier<AssistantState> {
  static const _key = 'assistant_conversations';
  static const _maxConversations = 50;

  @override
  AssistantState build() {
    final saved = ref
        .read(localStoreProvider)
        .readList(_key)
        .map((e) {
          try {
            return Conversation.fromJson((e as Map).cast<String, dynamic>());
          } catch (_) {
            return null;
          }
        })
        .whereType<Conversation>()
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return AssistantState(history: saved);
  }

  Future<void> send(String text) async {
    final q = text.trim();
    if (q.isEmpty || state.sending) return;
    final id = state.conversationId ?? DateTime.now().microsecondsSinceEpoch.toString();
    final context = [...state.messages.where((m) => !m.isError), ChatMessage('user', q)];
    state = state.copyWith(messages: [...state.messages, ChatMessage('user', q)], sending: true, conversationId: id);
    await _save(id, state.messages);

    ChatMessage reply;
    int? remaining = state.remaining;
    try {
      final loc = await ref.read(userLocationProvider.future);
      final res = (await ref.read(apiClientProvider).post('/ai/chat', {
        'messages': context.map((m) => m.toApi()).toList(),
        'context': {
          'lat': loc.point.lat,
          'lng': loc.point.lng,
          'exposureMinutes': ref.read(outdoorSessionProvider).minutesToday,
          'waterMlToday': ref.read(hydrationProvider).totalMl,
        },
      }) as Map)
          .cast<String, dynamic>();
      reply = ChatMessage('assistant', res['reply'] as String);
      // Recusas de assuntos internos não gastam pergunta e não trazem o contador.
      remaining = (res['remainingToday'] as num?)?.toInt() ?? remaining;
    } on ApiException catch (e) {
      reply = ChatMessage('assistant', e.message, isError: true);
      if (e.status == 429) remaining = 0;
    }

    // A pessoa pode ter fechado a conversa enquanto a resposta chegava:
    // a resposta vai para a conversa certa no histórico.
    final stillOpen = state.conversationId == id;
    final base = stillOpen ? state.messages : (_find(id)?.messages ?? context);
    final updated = [...base, reply];
    state = stillOpen
        ? state.copyWith(messages: updated, sending: false, remaining: remaining)
        : state.copyWith(sending: false, remaining: remaining);
    await _save(id, updated);
  }

  /// Fecha a conversa aberta (ela fica no histórico) e volta para o início.
  void close() => state = state.copyWith(messages: const [], sending: false, clearConversation: true);

  /// Começa uma conversa nova; a atual fica guardada no histórico.
  void newConversation() => close();

  /// Reabre uma conversa do histórico para continuar de onde parou.
  void open(String id) {
    final c = _find(id);
    if (c == null) return;
    state = state.copyWith(messages: c.messages, conversationId: c.id, sending: false);
  }

  Future<void> delete(String id) async {
    final history = state.history.where((c) => c.id != id).toList();
    state = state.conversationId == id
        ? state.copyWith(history: history, messages: const [], clearConversation: true)
        : state.copyWith(history: history);
    await _persist();
  }

  Future<void> clearHistory() async {
    state = state.copyWith(history: const [], messages: const [], clearConversation: true);
    await _persist();
  }

  Conversation? _find(String id) => state.history.where((c) => c.id == id).firstOrNull;

  Future<void> _save(String id, List<ChatMessage> messages) async {
    final firstQuestion = messages.firstWhere((m) => m.role == 'user', orElse: () => messages.first).text;
    final title = firstQuestion.length > 60 ? '${firstQuestion.substring(0, 57).trimRight()}…' : firstQuestion;
    final convo = Conversation(id: id, title: title, updatedAt: DateTime.now(), messages: messages);
    final history = [convo, ...state.history.where((c) => c.id != id)].take(_maxConversations).toList();
    state = state.copyWith(history: history);
    await _persist();
  }

  Future<void> _persist() =>
      ref.read(localStoreProvider).writeList(_key, state.history.map((c) => c.toJson()).toList());
}

final assistantProvider = NotifierProvider<AssistantController, AssistantState>(AssistantController.new);
