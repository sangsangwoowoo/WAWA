// models/grammar_history_model.dart

class GrammarHistory {
  final int id;
  final String transcribedText;
  final String correctedText;
  final List<String> grammarFeedback;
  final List<String> vocabularySuggestions;
  final DateTime createdAt;
  bool isFavorite;
  final bool isCorrect; // <-- [추가] 정답 여부 필드

  GrammarHistory({
    required this.id,
    required this.transcribedText,
    required this.correctedText,
    required this.grammarFeedback,
    required this.vocabularySuggestions,
    required this.createdAt,
    this.isFavorite = false,
    required this.isCorrect, // <-- [추가] 생성자에 추가
  });

  factory GrammarHistory.fromJson(Map<String, dynamic> json) {
    return GrammarHistory(
      id: json['id'],
      transcribedText: json['transcribed_text'] ?? '',
      correctedText: json['corrected_text'] ?? '',
      grammarFeedback: List<String>.from(json['grammar_feedback'] ?? []),
      vocabularySuggestions: List<String>.from(json['vocabulary_suggestions'] ?? []),
      createdAt: DateTime.parse(json['created_at']),
      isFavorite: json['is_favorite'] ?? false,
      isCorrect: json['is_correct'] ?? false, // <-- [추가] JSON 파싱 로직 추가
    );
  }
}

class GrammarStatistics {
  final int totalCount;
  final int correctCount;
  final int incorrectCount;
  final double accuracy;
  final double? recentAccuracy;

  GrammarStatistics({
    required this.totalCount,
    required this.correctCount,
    required this.incorrectCount,
    required this.accuracy,
    this.recentAccuracy,
  });

  factory GrammarStatistics.fromJson(Map<String, dynamic> json) {
    return GrammarStatistics(
      totalCount: json['total_count'],
      correctCount: json['correct_count'],
      incorrectCount: json['incorrect_count'],
      accuracy: (json['accuracy'] as num).toDouble(),
      recentAccuracy: (json['recent_accuracy'] as num?)?.toDouble(),
    );
  }
}