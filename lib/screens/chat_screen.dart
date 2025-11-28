import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_ai_app/widgets/chat_bubble.dart';
import 'package:local_ai_app/providers/chat_provider.dart';

import 'package:uuid/uuid.dart';

const uuid = Uuid();

class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key});

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  late TextEditingController inputController;

  @override
  void initState() {
    super.initState();
    inputController = TextEditingController();
  }

  @override
  void dispose() {
    inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final messages = ref.watch(chatProvider);
    final isLoading = ref.watch(isLoadingProvider);

        void sendMessage() {
          final text = inputController.text.trim();
          if (text.isNotEmpty && !isLoading) {
            // Create loading controller for state management
            final loadingController = StateController<bool>(true);
            
            // Use the actual sendMessage method with LLM integration
            ref.read(chatProvider.notifier).sendMessage(
              text,
              loadingController: loadingController,
            );
            inputController.clear();
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
        ],
      ),
    );
  }
}
