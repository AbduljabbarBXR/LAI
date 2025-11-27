import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_llm_plugin_platform_interface.dart';

/// An implementation of [LocalLlmPluginPlatform] that uses method channels.
class MethodChannelLocalLlmPlugin extends LocalLlmPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('local_llm_plugin');

  /// Event channel for receiving streaming tokens
  @visibleForTesting
  final eventChannel = const EventChannel('local_llm_plugin_stream');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }

  @override
  Future<String> loadModel(String modelPath) async {
    final result = await methodChannel.invokeMethod<String>('loadModel', {'modelPath': modelPath});
    return result ?? 'Model loaded';
  }

  @override
  Future<String> generateResponse(String prompt) async {
    final result = await methodChannel.invokeMethod<String>('generateResponse', {'prompt': prompt});
    return result ?? 'Response generated';
  }

  @override
  Future<String> freeModel() async {
    final result = await methodChannel.invokeMethod<String>('freeModel');
    return result ?? 'Model freed';
  }

  @override
  Future<void> generateResponseStreaming(
    String prompt, 
    StreamingCallback onToken,
    StreamingCompleteCallback onComplete
  ) async {
    // Listen to event channel for streaming data
    eventChannel.receiveBroadcastStream().listen(
      (dynamic event) {
        final Map<String, dynamic> data = event as Map<String, dynamic>;
        final String eventType = data['type'] as String;
        
        if (eventType == 'token') {
          final String token = data['token'] as String;
          onToken(token);
        } else if (eventType == 'complete') {
          final String fullResponse = data['response'] as String;
          onComplete(fullResponse);
        }
      },
      onError: (dynamic error) {
        print('Streaming error: $error');
        onComplete('Error: $error');
      },
    );

    // Start streaming on native side
    await methodChannel.invokeMethod<void>('generateResponseStreaming', {'prompt': prompt});
  }
}
