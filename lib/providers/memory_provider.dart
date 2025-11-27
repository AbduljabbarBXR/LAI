import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_ai_app/database/database.dart';
import 'package:local_ai_app/models/memory.dart';
import 'package:local_ai_app/services/embedding_service.dart';

// StateNotifier for memory list
class MemoryNotifier extends StateNotifier<List<Memory>> {
  final AppDatabase db;

  MemoryNotifier(this.db) : super([]);

  Future<void> loadMemories() async {
    state = await db.allMemories;
  }

  Future<void> addMemory(String content, List<double> vector, {String? id}) async {
    id ??= DateTime.now().millisecondsSinceEpoch.toString();
    final vectorBytes = embeddingService.vectorToBytes(vector);
    final entry = MemoriesCompanion(
      id: Value(id),
      textContent: Value(content),
      vectorEmbedding: Value(vectorBytes),
      createdAt: Value(DateTime.now()),
    );
    await db.addMemory(entry);
    await loadMemories(); // Refresh state
  }

  Future<List<Memory>> searchSimilar(List<double> queryVector, int limit) async {
    return await db.findSimilarMemories(queryVector, limit);
  }
}

final memoryProvider = StateNotifierProvider<MemoryNotifier, List<Memory>>((ref) {
  final db = ref.watch(sharedDatabaseProvider);
  return MemoryNotifier(db);
});
