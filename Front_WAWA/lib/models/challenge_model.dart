// models/challenge_model.dart

// 챌린지를 완료한 멤버의 정보를 담는 모델
class ChallengeParticipant {
  final String userId;
  final String userName;
  final DateTime completedAt;

  ChallengeParticipant({
    required this.userId,
    required this.userName,
    required this.completedAt,
  });

  factory ChallengeParticipant.fromJson(Map<String, dynamic> json) {
    return ChallengeParticipant(
      userId: json['user_id'],
      userName: json['user_name'],
      completedAt: DateTime.parse(json['completed_at']),
    );
  }
}

// 챌린지 목록에 표시될 메인 모델
class GroupChallenge {
  final int id;
  final String title;
  final String? description;
  final DateTime endDate;
  final String creatorId;
  final String creatorName;
  final List<ChallengeParticipant> participants;
  final bool userHasCompleted;

  GroupChallenge({
    required this.id,
    required this.title,
    this.description,
    required this.endDate,
    required this.creatorId,
    required this.creatorName,
    required this.participants,
    required this.userHasCompleted,
  });

  factory GroupChallenge.fromJson(Map<String, dynamic> json) {
    var participantsList = json['participants'] as List? ?? [];
    List<ChallengeParticipant> participants = participantsList
        .map((i) => ChallengeParticipant.fromJson(i))
        .toList();

    return GroupChallenge(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      endDate: DateTime.parse(json['end_date']),
      creatorId: json['creator_id'],
      creatorName: json['creator_name'],
      participants: participants,
      userHasCompleted: json['user_has_completed'] ?? false,
    );
  }
}

// (참고) 챌린지 인증 내역을 위한 모델
class ChallengeSubmission {
  final int id;
  final String userId;
  final String userName;
  final String? proofContent;
  final String? proofImageUrl;
  final String status;
  final DateTime submittedAt;

  ChallengeSubmission({
    required this.id,
    required this.userId,
    required this.userName,
    this.proofContent,
    this.proofImageUrl,
    required this.status,
    required this.submittedAt,
  });

  factory ChallengeSubmission.fromJson(Map<String, dynamic> json) {
    return ChallengeSubmission(
      id: json['id'],
      userId: json['user_id'],
      userName: json['user_name'],
      proofContent: json['proof_content'],
      proofImageUrl: json['proof_image_url'],
      status: json['status'],
      submittedAt: DateTime.parse(json['submitted_at']),
    );
  }
}