// lib/models/learning_progress_model.dart

class LearningProgress {
  final double overallProgress; // 전체 목표 달성률 (0.0 ~ 1.0)
  final ProgressDetail conversation;
  final ProgressDetail grammar;
  final ProgressDetail pronunciation;
  final String feedback; // 진척도 피드백 메시지

  LearningProgress({
    required this.overallProgress,
    required this.conversation,
    required this.grammar,
    required this.pronunciation,
    required this.feedback,
  });

  factory LearningProgress.fromJson(Map<String, dynamic> json) {
    return LearningProgress(
      overallProgress: (json['overall_progress'] ?? 0.0).toDouble(),
      conversation: ProgressDetail.fromJson(json['conversation'] ?? {}),
      grammar: ProgressDetail.fromJson(json['grammar'] ?? {}),
      pronunciation: ProgressDetail.fromJson(json['pronunciation'] ?? {}),
      feedback: json['feedback'] ?? '학습 기록이 부족하여 피드백을 생성할 수 없습니다.',
    );
  }
}

class ProgressDetail {
  final int goal;       // 설정한 목표 (분 또는 횟수)
  final int achieved;   // 달성한 양 (분 또는 횟수)
  final double progress; // 개별 달성률 (0.0 ~ 1.0)

  ProgressDetail({
    required this.goal,
    required this.achieved,
    required this.progress,
  });

  factory ProgressDetail.fromJson(Map<String, dynamic> json) {
    return ProgressDetail(
      goal: json['goal'] ?? 0,
      achieved: json['achieved'] ?? 0,
      progress: (json['progress'] ?? 0.0).toDouble(),
    );
  }
}