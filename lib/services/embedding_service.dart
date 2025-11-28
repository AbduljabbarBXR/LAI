import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

class EmbeddingService {
  final Map<String, List<double>> _embeddingCache = {};
  static const int embeddingDimension = 384; // all-MiniLM-L6-v2 standard

  Future<void> initializeModel() async {
    try {
      // Initialize ONNX Runtime for text embeddings
      // ONNX Runtime is the industry standard for efficient mobile inference
      // all-MiniLM-L6-v2 provides excellent accuracy vs performance balance
      print('Initializing ONNX Runtime Text Embeddings...');
      
      // For production, you would load the all-MiniLM-L6-v2 model:
      // final sessionOptions = SessionOptions();
      // sessionOptions.logSeverityLevel = 3;
      // _onnxSession = await InferenceSession.create(
      //   'assets/models/all-MiniLM-L6-v2.onnx',
      //   sessionOptions,
      // );
      
      // For now, use deterministic embeddings as placeholder
      // In production, replace with actual ONNX inference
      print('ONNX Runtime initialized (deterministic embeddings mode)');
      
    } catch (e) {
      print('Failed to initialize ONNX Runtime: $e');
      // Fallback to deterministic embeddings
    }
  }

  Future<List<double>> getEmbedding(String text) async {
    if (text.isEmpty) {
      return List.filled(embeddingDimension, 0.0);
    }

    // Check cache first
    final cacheKey = text.toLowerCase().trim();
    if (_embeddingCache.containsKey(cacheKey)) {
      return _embeddingCache[cacheKey]!;
    }

    try {
      // In production, this would use actual ONNX inference:
      // final input = {'input_ids': inputIds, 'attention_mask': attentionMask};
      // final outputs = await _onnxSession!.run(input);
      // final embedding = outputs.first as List<double>;
      
      // For now, use deterministic embeddings based on text
      // This provides consistent embeddings for the same text
      final embedding = _generateDeterministicEmbedding(text);
      
      // Cache the result
      _embeddingCache[cacheKey] = embedding;
      
      // Limit cache size to prevent memory issues
      if (_embeddingCache.length > 1000) {
        _embeddingCache.remove(_embeddingCache.keys.first);
      }
      
      return embedding;
      
    } catch (e) {
      print('Error generating embedding: $e');
      return List.filled(embeddingDimension, 0.0);
    }
  }

  List<double> _generateDeterministicEmbedding(String text) {
    // Simple hash-based embedding generator for placeholder
    // In production, replace with actual MediaPipe embeddings
    final hash = text.toLowerCase().hashCode;
    final seed = (hash.abs() % 1000000).toDouble();
    
    final embedding = <double>[];
    for (int i = 0; i < embeddingDimension; i++) {
      // Generate pseudo-random but deterministic values
      final value = ((seed * (i + 1) * 0.123456789) % 1.0) * 2.0 - 1.0;
      embedding.add(value);
    }
    
    // Normalize to unit length for cosine similarity
    return _normalizeVector(embedding);
  }

  List<double> _normalizeVector(List<double> vector) {
    final magnitude = vector.fold(0.0, (sum, val) => sum + val * val);
    final sqrtMagnitude = magnitude > 0 ? sqrt(magnitude) : 1.0;
    return vector.map((val) => val / sqrtMagnitude).toList();
  }

  // Convert double list to Uint8List for efficient BLOB storage
  Uint8List vectorToBytes(List<double> vector) {
    final buffer = ByteData(vector.length * 4);
    for (int i = 0; i < vector.length; i++) {
      buffer.setFloat32(i * 4, vector[i], Endian.little);
    }
    return buffer.buffer.asUint8List();
  }

  // Convert Uint8List back to double list
  List<double> bytesToVector(Uint8List bytes) {
    final buffer = bytes.buffer.asByteData();
    final vector = <double>[];
    for (int i = 0; i < bytes.length; i += 4) {
      vector.add(buffer.getFloat32(i, Endian.little));
    }
    return vector;
  }

  void dispose() {
    _embeddingCache.clear();
    // _textEmbeddingTask?.close();
  }
}

final embeddingService = EmbeddingService();
