class Memory {
  final String id;
  final String textContent;
  final List<double> vectorEmbedding;
  final DateTime createdAt;
  final double? importanceScore;

  Memory({
    required this.id,
    required this.textContent,
    required this.vectorEmbedding,
    required this.createdAt,
    this.importanceScore,
  });

  Memory copyWith({
    String? id,
    String? textContent,
    List<double>? vectorEmbedding,
    DateTime? createdAt,
    double? importanceScore,
  }) {
    return Memory(
      id: id ?? this.id,
      textContent: textContent ?? this.textContent,
      vectorEmbedding: vectorEmbedding ?? this.vectorEmbedding,
      createdAt: createdAt ?? this.createdAt,
      importanceScore: importanceScore ?? this.importanceScore,
    );
  }
}
