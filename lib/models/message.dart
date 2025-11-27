class Message {
  final String id;
  final String conversationId;
  final String content;
  final String sender; // User/AI
  final DateTime timestamp;
  final String source; // Local/Cloud
  final String? aiThoughts; // AI reasoning/explanation (hidden by default)
  final Duration? latency;
  final int? latencyMs; // For database compatibility

  Message({
    required this.id,
    required this.conversationId,
    required this.content,
    required this.sender,
    required this.timestamp,
    this.source = 'Local',
    this.aiThoughts,
    this.latency,
    this.latencyMs,
  });

  Message copyWith({
    String? id,
    String? conversationId,
    String? content,
    String? sender,
    DateTime? timestamp,
    String? source,
    String? aiThoughts,
    Duration? latency,
    int? latencyMs,
  }) {
    return Message(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      content: content ?? this.content,
      sender: sender ?? this.sender,
      timestamp: timestamp ?? this.timestamp,
      source: source ?? this.source,
      aiThoughts: aiThoughts ?? this.aiThoughts,
      latency: latency ?? this.latency,
      latencyMs: latencyMs ?? this.latencyMs,
    );
  }
}
