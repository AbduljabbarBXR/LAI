import 'package:local_llm_plugin/local_llm_plugin.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

typedef StreamingCallback = void Function(String token);
typedef StreamingCompleteCallback = void Function(String fullResponse);

class LlmService {
  LocalLlmPlugin _plugin;
  bool _modelLoaded = false;
  String? _loadedModelPath;
  bool _isStreaming = false;
  bool _isInitializing = false; // CRITICAL FIX: Prevent concurrent initialization

  // Constructor for production use (uses real plugin)
  LlmService() : _plugin = LocalLlmPlugin();

  // Constructor for testing (injects mock plugin)
  LlmService.withPlugin(this._plugin);

  // Initialize with a default model - CRITICAL FIX: Prevent multiple concurrent initialization
  Future<void> initialize() async {
    // Double-check pattern to prevent race conditions
    if (_modelLoaded) return;
    
    // Use a lock to prevent concurrent initialization
    if (_isInitializing) return;
    _isInitializing = true;
    
    try {
      // Use Gemma instruction-tuned model for better responses
      final modelPath = await _getModelPath('gemma-3-1B-it-QAT-Q4_0.gguf');
      if (await File(modelPath).exists()) {
        await loadModel(modelPath);
        print('Auto-loaded model from: $modelPath');
      } else {
        print('Model file not found at: $modelPath');
        // Fallback to tinyllama if gemma not available
        final fallbackPath = await _getModelPath('tinyllama-1.1b-chat-v1.0-q4_k_m.gguf');
        if (await File(fallbackPath).exists()) {
          await loadModel(fallbackPath);
          print('Fallback to tinyllama: $fallbackPath');
        } else {
          print('No model files available');
        }
      }
    } catch (e) {
      print('Failed to initialize LLM: $e');
    } finally {
      _isInitializing = false;
    }
  }

  Future<String> _getModelPath(String filename) async {
    final appDir = await getApplicationDocumentsDirectory();
    final modelDir = Directory('${appDir.path}/models');
    final modelPath = '${modelDir.path}/$filename';

    // Ensure directory exists
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }

    // Copy from assets if file doesn't exist
    if (!await File(modelPath).exists()) {
      try {
        final assetData = await rootBundle.load('assets/models/$filename');
        final bytes = assetData.buffer.asUint8List();
        await File(modelPath).writeAsBytes(bytes);
        print('Copied model from assets: $filename');
      } catch (e) {
        print('Failed to copy model from assets: $e');
      }
    }

    return modelPath;
  }

  Future<String> loadModel(String modelPath) async {
    final result = await _plugin.loadModel(modelPath);
    // FIX: Check for "loading started" instead of "successfully" 
    // since that's what the Kotlin plugin actually returns
    if (result.contains('loading started') || result.contains('successfully')) {
      _modelLoaded = true;
      _loadedModelPath = modelPath;
    }
    return result;
  }

  Future<String> generateResponse(String prompt) async {
    if (!_modelLoaded) {
      // Try to auto-initialize
      await initialize();
      if (!_modelLoaded) {
        return 'Error: No model loaded. Please ensure model file exists.';
      }
    }
    // Direct plugin call on main thread - MethodChannel requires main isolate
    try {
      return await _plugin.generateResponse(prompt);
    } catch (e) {
      print('Error generating response: $e');
      return 'Error: $e';
    }
  }

  Future<String> clearContext() async {
    // Method kept for potential future use if plugin exposes manual resets.
    return 'Context cleared';
  }

  Future<void> generateResponseStreaming(
    String prompt,
    StreamingCallback onToken,
    StreamingCompleteCallback onComplete,
    // PHASE 3: C++ handles question classification and token limits
    // No maxTokens parameter needed - let native handle everything
  ) async {
    if (!_modelLoaded) {
      await initialize();
      if (!_modelLoaded) {
        onComplete('Error: No model loaded. Please ensure model file exists.');
        return;
      }
    }

    if (_isStreaming) {
      onComplete('Error: Already streaming a response');
      return;
    }

    _isStreaming = true;
    
    try {
      // PHASE 3: C++ handles question classification and token limits
      // Direct call to native - no maxTokens parameter needed
      await _plugin.generateResponseStreaming(prompt, onToken, onComplete);
      
    } catch (e) {
      print('Error in streaming generation: $e');
      onComplete('Error: $e');
    } finally {
      _isStreaming = false;
    }
  }

  bool get isModelLoaded => _modelLoaded;
  String? get loadedModelPath => _loadedModelPath;
  bool get isStreaming => _isStreaming;
}

final llmService = LlmService();
