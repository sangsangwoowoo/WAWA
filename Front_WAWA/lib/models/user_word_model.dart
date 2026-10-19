// lib/models/user_word_model.dart

class UserWord {
  final int id;
  final String word;
  final String definition;
  final String? pronunciation;
  final String? englishExample;
  bool isMemorized;
  bool isFavorite;

  UserWord({
    required this.id,
    required this.word,
    required this.definition,
    this.pronunciation,
    this.englishExample,
    required this.isMemorized,
    required this.isFavorite,
  });

  factory UserWord.fromJson(Map<String, dynamic> json) {
    return UserWord(
      id: json['id'],
      word: json['word'],
      definition: json['definition'],
      pronunciation: json['pronunciation'],
      englishExample: json['english_example'],
      isMemorized: json['is_memorized'],
      isFavorite: json['is_favorite'] ?? false,
    );
  }
}