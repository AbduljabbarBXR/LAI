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
  String? conversationId;

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
    conversationId = newConversationId;
    await _loadMessages();
    // Call memory_clear to prevent KV cache contamination
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

    // Set loading state if controller provided
    if (loadingController != null) {
      loadingController.state = true;
    }

    try {
      // TODO: Restore memory integration once database setup is complete
      // For now, use minimal context
      final context = ""; // Empty context for initial testing

      // Smart limit: determine appropriate token limit based on question complexity
      final tokenLimit = _getSmartTokenLimit(content);
      
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

      // Use streaming response
      String accumulatedResponse = '';
      
      await llmService.generateResponseStreaming(
        prompt,
        maxTokens: tokenLimit, // Pass smart token limit
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
      // Clear loading state
      if (loadingController != null) {
        loadingController.state = false;
      }
      // Reset processing flag
      _isProcessing = false;
    }
  }

  /// Smart token limit based on question complexity
  /// Provides appropriate response lengths for different question types
  int _getSmartTokenLimit(String question) {
    final lowerQuestion = question.toLowerCase();
    final wordCount = question.split(' ').length;
    final charCount = question.length;
    
    // Quick facts: short questions asking for definitions or basic info
    if ((charCount < 50 && wordCount <= 8) ||
        lowerQuestion.startsWith('what is') ||
        lowerQuestion.startsWith('who is') ||
        lowerQuestion.startsWith('define') ||
        lowerQuestion.contains('?') && wordCount <= 10) {
      return 128; // Quick answer - 2-3 seconds
    }
    
    // Explanations: questions asking for detailed understanding
    if (lowerQuestion.startsWith('explain') ||
        lowerQuestion.startsWith('how does') ||
        lowerQuestion.startsWith('why does') ||
        lowerQuestion.startsWith('describe') ||
        wordCount > 10 && wordCount <= 25) {
      return 200; // Balanced explanation - 4-5 seconds
    }
    
    // Complex queries: longer questions requiring detailed analysis
    if (wordCount > 25 ||
        lowerQuestion.contains('analyze') ||
        lowerQuestion.contains('compare') ||
        lowerQuestion.contains('pros and cons') ||
        lowerQuestion.contains('advantages')) {
      return 256; // Detailed response - 5-6 seconds
    }
    
    // Default: moderate response for typical questions
    return 180; // Default reasonable length - 3-4 seconds
  }

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
