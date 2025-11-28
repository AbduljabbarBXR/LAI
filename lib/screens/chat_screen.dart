import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_ai_app/database/database.dart';
import 'package:local_ai_app/models/conversation.dart';
import 'package:local_ai_app/widgets/chat_bubble.dart';
import 'package:local_ai_app/providers/chat_provider.dart';
import 'package:local_ai_app/providers/conversation_provider.dart';

import 'package:uuid/uuid.dart';

const uuid = Uuid();

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late TextEditingController inputController;
  StateController<bool>? _currentLoadingController;

  @override
  void initState() {
    super.initState();
    inputController = TextEditingController();
  }

  @override
  void dispose() {
    inputController.dispose();
    _currentLoadingController?.dispose();
    super.dispose();
  }

  // Generate smart conversation title from first message
  String _generateSmartTitle(String firstMessage) {
    String lowerMessage = firstMessage.toLowerCase();

    if (lowerMessage.contains('what is') || lowerMessage.contains('what are')) {
      String topic = firstMessage.replaceFirst('What is', '').replaceFirst('What are', '').trim();
      return 'About ${topic}';
    } else if (lowerMessage.contains('how to') || lowerMessage.contains('how do')) {
      String topic = firstMessage.replaceFirst('How to', '').replaceFirst('How do', '').trim();
      return '${topic} Help';
    } else if (lowerMessage.contains('explain')) {
      String topic = firstMessage.replaceFirst('Explain', '').trim();
      return topic;
    } else if (lowerMessage.contains('help me') || lowerMessage.contains('help with')) {
      String topic = firstMessage.replaceFirst('Help me with', '').replaceFirst('Help me', '').replaceFirst('help with', '').trim();
      return '${topic} Help';
    } else if (lowerMessage.contains('write') || lowerMessage.contains('create')) {
      String topic = firstMessage.replaceFirst('Write', '').replaceFirst('write', '').replaceFirst('Create', '').replaceFirst('create', '').trim();
      return '${topic} Writing';
    } else if (lowerMessage.contains('compare') || lowerMessage.contains('difference between')) {
      String parts = firstMessage.replaceFirst('Compare', '').replaceFirst('compare', '').replaceFirst('difference between', '').trim();
      return parts.replaceAll(' and ', ' vs ');
    } else if (lowerMessage.contains('what\'s') || lowerMessage.contains('whats')) {
      final cleanedMessage = firstMessage.replaceFirst('What\'s', '').replaceFirst('whats', '').trim();
      return 'Question: $cleanedMessage';
    } else if (lowerMessage.contains('hello') || lowerMessage.contains('hi')) {
      return 'Greeting Chat';
    } else {
      List<String> words = firstMessage.split(' ').where((word) => word.isNotEmpty).take(3).toList();
      String title = words.join(' ');
      if (title.length > 30) {
        title = '${title.substring(0, 30)}...';
      }
      return title.isEmpty ? 'New Chat' : title;
    }
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final isLoading = _currentLoadingController?.state ?? false;

        void sendMessage() async {
          final text = inputController.text.trim();
          if (text.isNotEmpty && !isLoading) {
            // Create loading controller for proper async management
            final loadingController = StateController<bool>(true);
            _currentLoadingController = loadingController;
            
            try {
              // Check if we need to create a new conversation
              final selectedConversationId = ref.read(selectedConversationIdProvider);
              if (selectedConversationId == null) {
                // Create conversation using provider (returns the actual conversation ID)
                final conversationNotifier = ref.read(conversationProvider.notifier);
                final newConversationId = await conversationNotifier.createNewConversation(
                  firstMessage: text,
                );

                // Set the actual conversation ID as current (not a new one!)
                ref.read(selectedConversationIdProvider.notifier).state = newConversationId;
              }

              // Send message with loading controller - wait for AI response
              await ref.read(chatProvider.notifier).sendMessage(text, loadingController: loadingController);
              inputController.clear();
            } catch (e) {
              print('Error sending message: $e');
            } finally {
              // Set loading to false after everything completes
              loadingController.state = false;
              if (_currentLoadingController == loadingController) {
                _currentLoadingController = null;
              }
            }
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Local AI App'),
            backgroundColor: Colors.grey[50],
            foregroundColor: Colors.grey[900],
            elevation: 0,
            actions: [
              if (isLoading)
                Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[600]!),
                      ),
                    ),
                  ),
                ),
              IconButton(
                icon: Icon(Icons.settings, color: Colors.grey[700]),
                onPressed: () => Scaffold.of(context).openDrawer(),
              ),
            ],
          ),
          drawer: const SettingsDrawer(),
          backgroundColor: Colors.grey[50],
          body: Column(
            children: [
              Expanded(
                child: ListView.builder(
                  reverse: true, // New messages at bottom
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[messages.length - 1 - index];
                    return ChatBubble(message: message);
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  border: Border(
                    top: BorderSide(color: Colors.grey[200]!, width: 1),
                  ),
                ),
                child: SafeArea(
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(24),
                            border: Border.all(color: Colors.grey[300]!),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: inputController,
                                  textDirection: TextDirection.ltr,
                                  onSubmitted: (_) => sendMessage(),
                                  autofocus: true, // Auto-focus input when app opens
                                  decoration: InputDecoration(
                                    hintText: isLoading ? 'AI is thinking...' : 'Message Local AI App...',
                                    hintStyle: TextStyle(color: Colors.grey[500]),
                                    border: InputBorder.none,
                                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  ),
                                  maxLines: null,
                                  textInputAction: TextInputAction.newline,
                                  enabled: !isLoading,
                                ),
                              ),
                              IconButton(
                                icon: isLoading
                                    ? SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor: AlwaysStoppedAnimation<Color>(Colors.grey[400]!),
                                        ),
                                      )
                                    : Icon(Icons.send, color: Colors.grey[700], size: 20),
                                onPressed: isLoading ? null : sendMessage,
                                constraints: const BoxConstraints(
                                  minWidth: 32,
                                  minHeight: 32,
                                ),
                                padding: EdgeInsets.zero,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
  }
}

class SettingsDrawer extends StatelessWidget {
  const SettingsDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Colors.grey[100],
            ),
            child: Text(
              'Settings',
              style: TextStyle(
                color: Colors.grey[900],
                fontSize: 24,
              ),
            ),
          ),
          ListTile(
            title: const Text('API Keys (Cloud LLMs)'),
            onTap: () {/* TODO: Navigate to API key settings */},
          ),
          ListTile(
            title: const Text('Model Files'),
            onTap: () {/* TODO: Navigate to model settings */},
          ),
          ListTile(
            title: const Text('Brain Tab'),
            onTap: () {/* TODO: Navigate to brain/memory management */},
          ),
          // Chat history section under Brain Tab
          const Divider(),
          ListTile(
            title: const Text('Recent Chats', style: TextStyle(fontWeight: FontWeight.bold)),
            leading: Icon(Icons.chat, size: 20),
            contentPadding: EdgeInsets.symmetric(horizontal: 16),
          ),
          Container(
            height: 200, // Scrollable area for chat history
            child: ChatHistoryList(),
          ),
        ],
      ),
    );
  }
}

// Chat history list widget for settings drawer
class ChatHistoryList extends ConsumerStatefulWidget {
  @override
  ConsumerState<ChatHistoryList> createState() => _ChatHistoryListState();
}

class _ChatHistoryListState extends ConsumerState<ChatHistoryList> {
  String searchQuery = '';

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationProvider);
    final selectedConversationId = ref.watch(selectedConversationIdProvider);

    // Filter conversations based on search
    final filteredConversations = conversations.where((conv) =>
      conv.title.toLowerCase().contains(searchQuery.toLowerCase())
    ).toList();

    if (conversations.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Text(
          'No chat history yet',
          style: TextStyle(
            color: Colors.grey[600],
            fontSize: 14,
          ),
        ),
      );
    }

    return Column(
      children: [
        // Search field
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search conversations...',
              hintStyle: TextStyle(fontSize: 12),
              prefixIcon: Icon(Icons.search, size: 16),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(20),
                borderSide: BorderSide(color: Colors.grey[300]!),
              ),
              contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            style: TextStyle(fontSize: 12),
            onChanged: (query) {
              setState(() => searchQuery = query);
            },
          ),
        ),

        // Conversations list
        Expanded(
          child: ListView.builder(
            itemCount: filteredConversations.length,
            itemBuilder: (context, index) {
              final conversation = filteredConversations[index];
              final isSelected = selectedConversationId == conversation.id;

              return ListTile(
                leading: Icon(
                  isSelected ? Icons.chat : Icons.chat_bubble_outline,
                  size: 16,
                  color: isSelected ? Colors.blue[600] : Colors.grey[600],
                ),
                title: Text(
                  conversation.title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    color: isSelected ? Colors.blue[600] : Colors.black,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  conversation.updatedAt.toString().split(' ')[0],
                  style: TextStyle(
                    fontSize: 12,
                    color: isSelected ? Colors.blue[400] : Colors.grey[500],
                  ),
                ),
                tileColor: isSelected ? Colors.blue[50] : null,
                onTap: () async {
                  Navigator.pop(context);

                  // Switch to this conversation
                  ref.read(selectedConversationIdProvider.notifier).state = conversation.id;

                  // Load messages for this conversation
                  await ref.read(chatProvider.notifier).switchConversation(conversation.id);

                  // Update conversation timestamp for proper sorting
                  await ref.read(conversationProvider.notifier).updateConversationTimestamp(conversation.id);
                },
                onLongPress: () => _showConversationMenu(context, conversation, ref),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showConversationMenu(BuildContext context, ConversationModel conversation, WidgetRef ref) {
    final selectedConversationId = ref.read(selectedConversationIdProvider);

    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: Icon(Icons.delete, color: Colors.red),
            title: Text('Delete Conversation'),
            subtitle: Text('This action cannot be undone'),
            onTap: () async {
              Navigator.pop(context); // Close menu

              // Confirm deletion
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: Text('Delete "${conversation.title}"?'),
                  content: Text('All messages in this conversation will be permanently deleted.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      child: Text('Delete'),
                    ),
                  ],
                ),
              ) ?? false;

              if (confirmed) {
                // Delete the conversation
                await ref.read(conversationProvider.notifier).deleteConversation(conversation.id);

                // If this was the current conversation, clear it
                if (selectedConversationId == conversation.id) {
                  ref.read(selectedConversationIdProvider.notifier).state = null;
                  ref.read(chatProvider.notifier).switchConversation(null);
                }
              }
            },
          ),
        ],
      ),
    );
  }
}
