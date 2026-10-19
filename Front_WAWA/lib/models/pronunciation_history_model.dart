class PronunciationHistory {
  final String id;  // ✅ int → String
  final String sessionId;
  final String targetText;
  final double overallScore;
  final double pitchScore;
  final double rhythmScore;
  final double stressScore;
  final double phonemeScore;
  final double? fluencyScore;
  final double? confidence;
  final String? rateStatus;
  final String? fluencyStatus;
  final List<String>? misstressedWords;
  final List<String> detailedFeedback;
  final List<String> suggestions;
  final DateTime createdAt;

  PronunciationHistory({
    required this.id,
    required this.sessionId,
    required this.targetText,
    required this.overallScore,
    required this.pitchScore,
    required this.rhythmScore,
    required this.stressScore,
    required this.fluencyScore,
    required this.phonemeScore,
    this.confidence,
    this.rateStatus,
    this.fluencyStatus,
    this.misstressedWords,
    required this.detailedFeedback,
    required this.suggestions,
    required this.createdAt,
  });

  factory PronunciationHistory.fromJson(Map<String, dynamic> json) {
    return PronunciationHistory(
      id: json['id'].toString(),  // ✅ toString() 추가
      sessionId: json['session_id'],
      targetText: json['target_text'],
      overallScore: (json['overall_score'] as num).toDouble(),
      pitchScore: (json['pitch_score'] as num).toDouble(),
      rhythmScore: (json['rhythm_score'] as num).toDouble(),
      stressScore: (json['stress_score'] as num).toDouble(),
      phonemeScore: (json['phoneme_score'] as num? ?? 0.0).toDouble(),
      fluencyScore: json['fluency_score'] != null
          ? (json['fluency_score'] as num).toDouble()
          : null,
      confidence: json['confidence'] != null
          ? (json['confidence'] as num).toDouble()
          : null,
      rateStatus: json['rate_status'],
      fluencyStatus: json['fluency_status'],
      misstressedWords: json['misstressed_words'] != null
          ? List<String>.from(json['misstressed_words'])
          : null,
      detailedFeedback: List<String>.from(json['detailed_feedback'] ?? []),
      suggestions: List<String>.from(json['suggestions'] ?? []),
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class PronunciationStatistics {
  final int totalCount;
  final double averageOverall;
  final double averagePitch;
  final double averageRhythm;
  final double averageStress;
  final double averageFluency;
  final double averagePhoneme;
  final double? recentImprovement;

  PronunciationStatistics({
    required this.totalCount,
    required this.averageOverall,
    required this.averagePitch,
    required this.averageRhythm,
    required this.averageStress,
    required this.averageFluency,
    required this.averagePhoneme,
    this.recentImprovement,
  });

  factory PronunciationStatistics.fromJson(Map<String, dynamic> json) {
    return PronunciationStatistics(
      totalCount: json['total_count'],
      averageOverall: (json['average_overall'] as num).toDouble(),
      averagePitch: (json['average_pitch'] as num).toDouble(),
      averageRhythm: (json['average_rhythm'] as num).toDouble(),
      averageStress: (json['average_stress'] as num).toDouble(),
      averageFluency: (json['average_fluency'] as num).toDouble(),
      averagePhoneme: (json['average_phoneme'] as num? ?? 0.0).toDouble(),
      recentImprovement: json['recent_improvement'] != null
          ? (json['recent_improvement'] as num).toDouble()
          : null,
    );
  }
}