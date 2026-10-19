// models/wordbook_model.dart

class Wordbook {
  final int id;
  final String name;
  final String userId;
  final DateTime createdAt;
  final int wordCount;

  Wordbook({
    required this.id,
    required this.name,
    required this.userId,
    required this.createdAt,
    required this.wordCount,
  });

  factory Wordbook.fromJson(Map<String, dynamic> json) {
    return Wordbook(
      id: json['id'],
      name: json['name'],
      userId: json['user_id'],
      createdAt: DateTime.parse(json['created_at']),
      wordCount: json['word_count'] ?? 0,
    );
  }
}