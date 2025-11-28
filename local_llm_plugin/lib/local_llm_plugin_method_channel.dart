import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'local_llm_plugin_platform_interface.dart';

/// An implementation of [LocalLlmPluginPlatform] that uses method channels.
class MethodChannelLocalLlmPlugin extends LocalLlmPluginPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('local_llm_plugin');

  // Handler for streaming callbacks - must be managed properly
  Future<dynamic> Function(MethodCall)? _streamingHandler;
  
  /// Event channel for receiving streaming tokens
  @visibleForTesting
  final eventChannel = const EventChannel('local_llm_plugin_stream');
  
  MethodChannelLocalLlmPlugin() {
    // Set wrapper handler that delegates to active handler
    methodChannel.setMethodCallHandler(_wrapperHandler);
  }

  /// Default method call handler for streaming messages
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    // Default implementation returns null for unimplemented methods
    return null;
  }
  
  /// Clean up streaming handler - call when streaming is done
  void _cleanupStreamingHandler() {
    _streamingHandler = null;
  }
  
  /// Wrapper handler that delegates to active handler or default
  Future<dynamic> _wrapperHandler(MethodCall call) async {
    if (_streamingHandler != null) {
      // Delegate to streaming handler if active
      return await _streamingHandler!(call);
    } else {
      // Use default handler for other methods
      return await _handleMethodCall(call);
    }
  }

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
    StreamingCompleteCallback onComplete, {
    int maxTokens = 200, // Smart limit parameter
  }) async {
    // CRITICAL FIX: Set streaming handler (wrapper will delegate to it)
    _streamingHandler = (MethodCall call) async {
      if (call.method == 'streaming_token') {
        final String token = call.arguments as String;
        onToken(token);
      } else if (call.method == 'streaming_complete') {
        final String fullResponse = call.arguments as String;
        onComplete(fullResponse);
        // CRITICAL FIX: Clean up handler after streaming completes
        _cleanupStreamingHandler();
      } else if (call.method == 'streaming_error') {
        final String error = call.arguments as String;
        onComplete('Error: $error');
        // CRITICAL FIX: Clean up handler after error
        _cleanupStreamingHandler();
      }
    };
    
    // Start streaming on native side - wrapper handler will handle the delegation
    await methodChannel.invokeMethod<void>('generateResponseStreaming', {
      'prompt': prompt,
      'maxTokens': maxTokens, // Pass smart token limit to native
    });
  }
}
