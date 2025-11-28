
import 'local_llm_plugin_platform_interface.dart';

typedef StreamingCallback = void Function(String token);
typedef StreamingCompleteCallback = void Function(String fullResponse);

class LocalLlmPlugin {
  Future<String?> getPlatformVersion() {
    return LocalLlmPluginPlatform.instance.getPlatformVersion();
  }

  Future<String> loadModel(String modelPath) {
    return LocalLlmPluginPlatform.instance.loadModel(modelPath);
  }

  Future<String> generateResponse(String prompt) {
    return LocalLlmPluginPlatform.instance.generateResponse(prompt);
  }

  Future<void> generateResponseStreaming(
    String prompt, 
    StreamingCallback onToken,
    StreamingCompleteCallback onComplete,
    // PHASE 3: C++ handles question classification and smart token limits
    // No maxTokens parameter - let native handle everything
  ) {
    // Direct call to platform implementation
    return LocalLlmPluginPlatform.instance.generateResponseStreaming(
      prompt, 
      onToken, 
      onComplete,
    );
  }
}
