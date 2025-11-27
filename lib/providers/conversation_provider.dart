import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_ai_app/database/database.dart';
import 'package:local_ai_app/models/conversation.dart';

// Provider for selected conversation id
final selectedConversationIdProvider = StateProvider<String?>((ref) => null);

// StateNotifier for managing conversations
class ConversationNotifier extends StateNotifier<List<ConversationModel>> {
  final AppDatabase database;

  ConversationNotifier(this.database) : super([]) {
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    final dbConversations = await database.getAllConversations();
    state = dbConversations.map((c) => ConversationModel(
      id: c.id,
      title: c.title,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    )).toList();
  }

  Future<void> createNewConversation({String? title, String? firstMessage}) async {
    final now = DateTime.now();
    final conversationId = now.millisecondsSinceEpoch.toString();

    // Generate smart title from first message if provided
    final smartTitle = title ?? (firstMessage != null ? ConversationModel.generateSmartTitle(firstMessage) : 'New Chat');

    final entry = ConversationsCompanion.insert(
      id: conversationId,
      title: smartTitle,
      createdAt: now,
      updatedAt: now,
    );

    await database.insertConversation(entry);

    // Add to state
    final newConversation = ConversationModel(
      id: conversationId,
      title: smartTitle,
      createdAt: now,
      updatedAt: now,
    );

    state = [newConversation, ...state];
  }

  Future<void> deleteConversation(String conversationId) async {
    // Delete conversation and its messages from database
    await database.deleteConversation(conversationId);
    await database.deleteMessagesForConversation(conversationId);

    // Remove from state
    state = state.where((c) => c.id != conversationId).toList();
  }

  Future<void> updateConversationTitle(String conversationId, String newTitle) async {
    final conversation = state.firstWhere((c) => c.id == conversationId);
    final updatedConversation = conversation.copyWith(title: newTitle, updatedAt: DateTime.now());

    final entry = ConversationsCompanion(
      id: Value(updatedConversation.id),
      title: Value(updatedConversation.title),
      createdAt: Value(updatedConversation.createdAt),
      updatedAt: Value(updatedConversation.updatedAt),
    );

    await database.updateConversation(entry);

    // Update state
    state = state.map((c) => c.id == conversationId ? updatedConversation : c).toList();
  }

  Future<void> updateConversationTimestamp(String conversationId) async {
    final now = DateTime.now();
    final conversation = state.firstWhere((c) => c.id == conversationId);
    final updatedConversation = conversation.copyWith(updatedAt: now);

    final entry = ConversationsCompanion(
      id: Value(updatedConversation.id),
      title: Value(updatedConversation.title),
      createdAt: Value(updatedConversation.createdAt),
      updatedAt: Value(updatedConversation.updatedAt),
    );

    await database.updateConversation(entry);

    // Update state and reorder (most recent first)
    state = state.map((c) => c.id == conversationId ? updatedConversation : c).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }
}

// Provider for the conversation state
final conversationProvider = StateNotifierProvider<ConversationNotifier, List<ConversationModel>>((ref) {
  final database = ref.watch(sharedDatabaseProvider);
  return ConversationNotifier(database);
});
