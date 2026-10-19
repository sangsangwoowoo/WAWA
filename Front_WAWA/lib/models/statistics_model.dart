// lib/models/statistics_model.dart

// 전체 누적 통계
class OverallStats {
  final int totalConversationDuration;
  final int totalGrammarCount;
  final int totalPronunciationCount;

  OverallStats({
    required this.totalConversationDuration,
    required this.totalGrammarCount,
    required this.totalPronunciationCount,
  });

  factory OverallStats.fromJson(Map<String, dynamic> json) {
    return OverallStats(
      totalConversationDuration: json['total_conversation_duration'] ?? 0,
      totalGrammarCount: json['total_grammar_count'] ?? 0,
      totalPronunciationCount: json['total_pronunciation_count'] ?? 0,
    );
  }
}

// 목표 대비 진척도 통계
class ProgressStats {
  final double conversationProgress;
  final double grammarProgress;
  final double pronunciationProgress;

  ProgressStats({
    required this.conversationProgress,
    required this.grammarProgress,
    required this.pronunciationProgress,
  });

  factory ProgressStats.fromJson(Map<String, dynamic> json) {
    return ProgressStats(
      conversationProgress: (json['conversation_progress'] ?? 0.0).toDouble(),
      grammarProgress: (json['grammar_progress'] ?? 0.0).toDouble(),
      pronunciationProgress: (json['pronunciation_progress'] ?? 0.0).toDouble(),
    );
  }
}

// API 최종 응답 모델
class StatisticsResponse {
  final OverallStats overallStats;
  final ProgressStats? progressStats;
  final String? feedback;

  StatisticsResponse({required this.overallStats, this.progressStats, this.feedback});

  factory StatisticsResponse.fromJson(Map<String, dynamic> json) {
    return StatisticsResponse(
      overallStats: OverallStats.fromJson(json['overall_statistics']),
      progressStats: json['progress_statistics'] != null
          ? ProgressStats.fromJson(json['progress_statistics'])
          : null,
      feedback: json['feedback'],
    );
  }
}