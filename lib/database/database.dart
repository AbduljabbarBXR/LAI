import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_ai_app/models/memory.dart' as memory_model;
import 'package:local_ai_app/services/embedding_service.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'local_ai_app.sqlite'));
    return NativeDatabase(file);
  });
}

@DataClassName('ConversationEntry')
class Conversations extends Table {
  TextColumn get id => text()();
  TextColumn get title => text().withLength(min: 1, max: 200)();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MessageEntry')
class Messages extends Table {
  TextColumn get id => text()();
  TextColumn get conversationId => text().references(Conversations, #id)();
  TextColumn get content => text()();
  TextColumn get sender => text()();
  DateTimeColumn get timestamp => dateTime()();
  TextColumn get source => text().withDefault(const Constant('Local'))();
  TextColumn get aiThoughts => text().nullable()();
  IntColumn get latencyMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('MemoryEntry')
class Memories extends Table {
  TextColumn get id => text()();
  TextColumn get textContent => text()();
  BlobColumn get vectorEmbedding => blob()();
  DateTimeColumn get createdAt => dateTime()();
  RealColumn get importanceScore => real().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [Conversations, Messages, Memories])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  Future<List<ConversationEntry>> getAllConversations() {
    final query = select(conversations)
      ..orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]);
    return query.get();
  }

  Future<void> insertConversation(Insertable<ConversationEntry> entry) {
    return into(conversations).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<void> updateConversation(Insertable<ConversationEntry> entry) {
    return update(conversations).replace(entry);
  }

  Future<void> deleteConversation(String id) {
    return (delete(conversations)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> deleteMessagesForConversation(String conversationId) {
    return (delete(messages)..where((tbl) => tbl.conversationId.equals(conversationId))).go();
  }

  Future<List<MessageEntry>> getMessagesForConversation(String conversationId) {
    final query = select(messages)
      ..where((tbl) => tbl.conversationId.equals(conversationId))
      ..orderBy([(tbl) => OrderingTerm.asc(tbl.timestamp)]);
    return query.get();
  }

  Future<int> insertMessage(Insertable<MessageEntry> entry) {
    return into(messages).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<List<memory_model.Memory>> get allMemories async {
    final rows = await (select(memories)
          ..orderBy([(tbl) => OrderingTerm.desc(tbl.createdAt)]))
        .get();
    return rows.map(_toMemoryModel).toList();
  }

  Future<void> addMemory(Insertable<MemoryEntry> entry) {
    return into(memories).insert(entry, mode: InsertMode.insertOrReplace);
  }

  Future<List<memory_model.Memory>> findSimilarMemories(
    List<double> queryVector,
    int limit,
  ) async {
    if (queryVector.isEmpty) {
      return [];
    }

    final rows = await select(memories).get();
    final scored = rows
        .map((row) {
          final vector = _vectorFromBytes(row.vectorEmbedding);
          final score = _cosineSimilarity(queryVector, vector);
          return _MemoryScore(row: row, score: score);
        })
        .where((entry) => !entry.score.isNaN)
        .toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.take(limit).map((entry) => _toMemoryModel(entry.row)).toList();
  }

  memory_model.Memory _toMemoryModel(MemoryEntry entry) {
    return memory_model.Memory(
      id: entry.id,
      textContent: entry.textContent,
      vectorEmbedding: _vectorFromBytes(entry.vectorEmbedding),
      createdAt: entry.createdAt,
      importanceScore: entry.importanceScore,
    );
  }

  List<double> _vectorFromBytes(Uint8List bytes) {
    if (bytes.isEmpty) {
      return const [];
    }
    return embeddingService.bytesToVector(bytes);
  }

  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.isEmpty || b.isEmpty || a.length != b.length) {
      return double.nan;
    }

    double dot = 0;
    double magA = 0;
    double magB = 0;

    for (var i = 0; i < a.length; i++) {
      final aVal = a[i];
      final bVal = b[i];
      dot += aVal * bVal;
      magA += aVal * aVal;
      magB += bVal * bVal;
    }

    if (magA == 0 || magB == 0) {
      return double.nan;
    }

    return dot / (math.sqrt(magA) * math.sqrt(magB));
  }
}

class _MemoryScore {
  const _MemoryScore({required this.row, required this.score});

  final MemoryEntry row;
  final double score;
}

final sharedDatabaseProvider = Provider<AppDatabase>((ref) {
  final database = AppDatabase();
  ref.onDispose(database.close);
  return database;
});

