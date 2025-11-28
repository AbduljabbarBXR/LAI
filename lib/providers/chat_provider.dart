import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_ai_app/database/database.dart';
import 'package:local_ai_app/models/message.dart';
import 'package:local_ai_app/providers/conversation_provider.dart';
import 'package:local_ai_app/services/llm_service.dart';

// Import the real embedding service
import 'package:local_ai_app/services/embedding_service.dart';

// StateNotifier for managing chat messages
class ChatNotifier extends StateNotifier<List<Message>> {
  final EmbeddingService embeddingService;
  final LlmService llmService;
  final AppDatabase database;
  final String? conversationId;

  bool _isProcessing = false;

  ChatNotifier(this.embeddingService, this.llmService, this.database, this.conversationId) : super([]) {
    if (conversationId != null) {
      _loadMessages();
    }
  }

  Future<void> _loadMessages() async {
    if (conversationId == null) return;
    final dbMessages = await database.getMessagesForConversation(conversationId!);
    state = dbMessages.map((m) => Message(
      id: m.id,
      conversationId: m.conversationId,
      content: m.content,
      sender: m.sender,
      timestamp: m.timestamp,
      source: m.source,
      aiThoughts: m.aiThoughts,
      latency: m.latencyMs != null ? Duration(milliseconds: m.latencyMs!) : null,
      latencyMs: m.latencyMs,
    )).toList();
  }

  Future<void> _saveMessage(Message message) async {
    if (conversationId == null) {
      return;
    }

    final entry = MessagesCompanion(
      id: Value(message.id),
      conversationId: Value(conversationId!),
      content: Value(message.content),
      sender: Value(message.sender),
      timestamp: Value(message.timestamp),
      source: Value(message.source),
      aiThoughts: Value(message.aiThoughts),
      latencyMs: Value(message.latency?.inMilliseconds),
    );
    await database.insertMessage(entry);
  }

  Future<void> switchConversation(String? newConversationId) async {
    // Note: conversationId is final and set by provider dependency
    // This method is mainly for clearing context when switching
    await llmService.clearContext();
  }



  // Add a new message
  void addMessage(Message message) {
    state = [...state, message];
  }

  Future<void> sendMessage(String content, {StateController<bool>? loadingController}) async {
    // Prevent multiple simultaneous requests
    if (_isProcessing) {
      print('Request already in progress, ignoring duplicate send');
      return;
    }

    _isProcessing = true;

    // Add user message
    final userMessage = Message(
      id: DateTime.now().toString(),
      conversationId: conversationId ?? 'default',
      content: content,
      sender: 'user',
      timestamp: DateTime.now(),
    );
    state = [...state, userMessage];
    await _saveMessage(userMessage);

    // Set loading state for controller only (global state managed by widget)
    loadingController?.state = true;

    try {
      // Clean prompt format to prevent contamination and improve quality
      final prompt = 'User: $content\nAssistant: Respond in plain text without markdown formatting.';

      // Create streaming AI message that we'll update as tokens arrive
      final aiMessageId = DateTime.now().millisecondsSinceEpoch.toString();
      final streamingMessage = Message(
        id: aiMessageId,
        conversationId: conversationId ?? 'default',
        content: '', // Start empty, add tokens as they arrive
        sender: 'ai',
        timestamp: DateTime.now(),
        source: 'Local',
      );

      // Add empty AI message to start streaming
      state = [...state, streamingMessage];
      await _saveMessage(streamingMessage);

      // Use streaming response - C++ handles classification
      String accumulatedResponse = '';

      await llmService.generateResponseStreaming(
        prompt,
        (String token) {
          // Called for each token as it arrives
          accumulatedResponse += token;

          // Update the message with accumulated response
          final updatedMessage = streamingMessage.copyWith(content: accumulatedResponse);
          state = [
            ...state.where((msg) => msg.id != aiMessageId),
            updatedMessage
          ];
        },
        (String fullResponse) {
          // Called when streaming is complete
          final parts = fullResponse.split('|');
          final mainResponse = parts.isNotEmpty ? parts[0] : fullResponse;
          final aiThoughts = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;

          // Update final message with complete response
          final finalMessage = streamingMessage.copyWith(
            content: mainResponse,
            aiThoughts: aiThoughts,
          );

          state = [
            ...state.where((msg) => msg.id != aiMessageId),
            finalMessage
          ];

          // Save the final message
          _saveMessage(finalMessage);
        },
      );

    } catch (e) {
      // Add error message as AI response
      final errorMessage = Message(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        conversationId: conversationId ?? 'default',
        content: 'Error: Failed to generate response - $e',
        sender: 'ai',
        timestamp: DateTime.now(),
        source: 'Error',
      );
      state = [...state, errorMessage];
    } finally {
      // Reset processing flag and loading state
      loadingController?.state = false;
      _isProcessing = false;
    }
  }

  // PHASE 3: Removed _getSmartTokenLimit method
  // Question classification now handled by C++ for better performance
  // Token limits are calculated natively based on question type

  // Clear all messages
  void clearMessages() {
    state = [];
  }
}

// Providers
final llmServiceProvider = StateProvider<LlmService>((ref) => LlmService());

// Provider for the chat state with database integration
final chatProvider = StateNotifierProvider<ChatNotifier, List<Message>>((ref) {
  final llmService = ref.watch(llmServiceProvider);
  final database = ref.watch(sharedDatabaseProvider);
  final conversationId = ref.watch(selectedConversationIdProvider);
  // Use the global embedding service instance
  return ChatNotifier(embeddingService, llmService, database, conversationId);
});

// Provider for the current user input
final userInputProvider = StateProvider<String>((ref) => '');

// Provider for loading state
final isLoadingProvider = StateProvider<bool>((ref) => false);
