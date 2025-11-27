import 'package:local_llm_plugin/local_llm_plugin.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as path;

typedef StreamingCallback = void Function(String token);
typedef StreamingCompleteCallback = void Function(String fullResponse);

class LlmService {
  final LocalLlmPlugin _plugin = LocalLlmPlugin();
  bool _modelLoaded = false;
  String? _loadedModelPath;
  bool _isStreaming = false;

  // Initialize with a default model
  Future<void> initialize() async {
    if (_modelLoaded) return;

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
    if (result.contains('successfully')) {
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
    StreamingCompleteCallback onComplete
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
      // For now, use the regular generateResponse and simulate streaming
      // This is a temporary solution until we fix the native streaming
      final response = await _plugin.generateResponse(prompt);
      
      // Simulate streaming by sending tokens one by one
      final parts = response.split('|');
      final mainResponse = parts.isNotEmpty ? parts[0] : response;
      final aiThoughts = parts.length > 1 && parts[1].isNotEmpty ? parts[1] : null;
      
      // Split response into words and send them as "tokens"
      final words = mainResponse.split(' ');
      String accumulatedResponse = '';
      
      for (int i = 0; i < words.length; i++) {
        final word = words[i];
        final token = i == 0 ? word : ' $word';
        accumulatedResponse += token;
        
        onToken(token);
        
        // Small delay to simulate streaming
        await Future.delayed(Duration(milliseconds: 50));
      }
      
      onComplete(response);
      
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
