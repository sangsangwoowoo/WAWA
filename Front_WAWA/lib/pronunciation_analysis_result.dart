class PronunciationAnalysisResult {
  final double overallScore;
  final double pitchScore;
  final double rhythmScore;
  final double stressScore;
  final double fluencyScore;
  final double phonemeScore;
  final List<String> detailedFeedback;
  final List<String> suggestions;
  final String grade;
  final List<String> improvementPriority;
  final String? sessionId;

  PronunciationAnalysisResult({
    required this.overallScore,
    required this.pitchScore,
    required this.rhythmScore,
    required this.stressScore,
    required this.fluencyScore,
    required this.phonemeScore,
    required this.detailedFeedback,
    required this.suggestions,
    required this.grade,
    required this.improvementPriority,
    this.sessionId,
  });

  // ▼▼▼ [핵심 수정] 이 fromJson 생성자를 새로운 데이터 구조에 맞게 수정합니다. ▼▼▼
  factory PronunciationAnalysisResult.fromJson(Map<String, dynamic> json) {
    // 백엔드에서 'scores'와 'feedback' 객체 없이 바로 전달되는 값들을 파싱합니다.
    return PronunciationAnalysisResult(
      overallScore: (json['overall_score'] as num?)?.toDouble() ?? 0.0,
      pitchScore: (json['pitch_score'] as num?)?.toDouble() ?? 0.0,
      rhythmScore: (json['rhythm_score'] as num?)?.toDouble() ?? 0.0,
      stressScore: (json['stress_score'] as num?)?.toDouble() ?? 0.0,
      fluencyScore: (json['fluency_score'] as num?)?.toDouble() ?? 0.0,
      phonemeScore: (json['phoneme_score'] as num? ?? 0.0).toDouble(),
      detailedFeedback: List<String>.from(json['detailed_feedback'] ?? []),
      suggestions: List<String>.from(json['suggestions'] ?? []),
      grade: json['grade'] as String? ?? 'N/A',
      improvementPriority: List<String>.from(json['improvement_priority'] ?? []),
      sessionId: json['session_id'] as String?,
    );
  }
}