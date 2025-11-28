import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'local_llm_plugin_method_channel.dart';

typedef StreamingCallback = void Function(String token);
typedef StreamingCompleteCallback = void Function(String fullResponse);

abstract class LocalLlmPluginPlatform extends PlatformInterface {
  /// Constructs a LocalLlmPluginPlatform.
  LocalLlmPluginPlatform() : super(token: _token);

  static final Object _token = Object();

  static LocalLlmPluginPlatform _instance = MethodChannelLocalLlmPlugin();

  /// The default instance of [LocalLlmPluginPlatform] to use.
  ///
  /// Defaults to [MethodChannelLocalLlmPlugin].
  static LocalLlmPluginPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [LocalLlmPluginPlatform] when
  /// they register themselves.
  static set instance(LocalLlmPluginPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  Future<String> loadModel(String modelPath) {
    throw UnimplementedError('loadModel() has not been implemented.');
  }

  Future<String> generateResponse(String prompt) {
    throw UnimplementedError('generateResponse() has not been implemented.');
  }

  Future<String> freeModel() {
    throw UnimplementedError('freeModel() has not been implemented.');
  }

  Future<void> generateResponseStreaming(
    String prompt, 
    StreamingCallback onToken,
    StreamingCompleteCallback onComplete, {
    int maxTokens = 200, // Smart limit parameter
  }) {
    throw UnimplementedError('generateResponseStreaming() has not been implemented.');
  }
}
