class ConversationModel {
  final String id;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConversationModel({
    required this.id,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  ConversationModel copyWith({
    String? id,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ConversationModel(
      id: id ?? this.id,
      title: title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // Extract first sentence from text for smart title generation
  static String generateSmartTitle(String text) {
    if (text.isEmpty) return 'New Chat';

    // Clean up the text
    final cleaned = text.trim().replaceAll(RegExp(r'\s+'), ' ');

    // Find first complete sentence (ends with ., !, or ?)
    final sentenceEndings = RegExp(r'[.!?]');
    final match = sentenceEndings.firstMatch(cleaned);

    if (match != null) {
      final sentence = cleaned.substring(0, match.end);
      // Limit to reasonable title length (max 60 chars)
      if (sentence.length <= 60) {
        return sentence.trim();
      }
    }

    // Fallback: first 50 characters followed by ellipsis if needed
    final truncated = cleaned.length > 50 ? '${cleaned.substring(0, 50)}...' : cleaned;
    return truncated.isEmpty ? 'New Chat' : truncated;
  }
}
