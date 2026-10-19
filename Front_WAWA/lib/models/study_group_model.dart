class StudyGroup {
  final int id;
  final String name;
  final String? description;
  final String createdBy;
  final String? creatorName;
  final int maxMembers;
  final int memberCount;
  final bool isMember;
  final bool isOwner;
  final bool requiresApproval; // << [추가] 가입 승인 필요 여부
  final DateTime createdAt;

  StudyGroup({
    required this.id,
    required this.name,
    this.description,
    required this.createdBy,
    this.creatorName,
    required this.maxMembers,
    required this.memberCount,
    required this.isMember,
    required this.isOwner,
    required this.requiresApproval, // << [추가]
    required this.createdAt,
  });

  factory StudyGroup.fromJson(Map<String, dynamic> json) {
    return StudyGroup(
      id: json['id'],
      name: json['name'],
      description: json['description'],
      createdBy: json['created_by'],
      creatorName: json['creator_name'],
      maxMembers: json['max_members'],
      memberCount: json['member_count'],
      isMember: json['is_member'],
      isOwner: json['is_owner'],
      requiresApproval: json['requires_approval'] ?? false, // << [추가] JSON 파싱 로직
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}

class GroupMember {
  final String userId;
  final String userName;
  final String role;
  final DateTime joinedAt;

  GroupMember({
    required this.userId,
    required this.userName,
    required this.role,
    required this.joinedAt,
  });

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      userId: json['user_id'],
      userName: json['user_name'],
      role: json['role'],
      joinedAt: DateTime.parse(json['joined_at']),
    );
  }
}

// << [추가] 그룹 내 채팅 메시지를 위한 모델 클래스 >>
class StudyGroupMessage {
  final int id;
  final int groupId;
  final String userId;
  final String userName;
  final String content;
  final DateTime createdAt;

  StudyGroupMessage({
    required this.id,
    required this.groupId,
    required this.userId,
    required this.userName,
    required this.content,
    required this.createdAt,
  });

  factory StudyGroupMessage.fromJson(Map<String, dynamic> json) {
    return StudyGroupMessage(
      id: json['id'],
      groupId: json['group_id'],
      userId: json['user_id'],
      userName: json['user_name'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']).toLocal(),
    );
  }
}

class StudyGroupJoinRequest {
  final int requestId;
  final String userId;
  final String userName;
  final DateTime requestedAt;

  StudyGroupJoinRequest({
    required this.requestId,
    required this.userId,
    required this.userName,
    required this.requestedAt,
  });

  factory StudyGroupJoinRequest.fromJson(Map<String, dynamic> json) {
    print(json);

    // ▼▼▼ 여기에 try-catch 구문을 추가해주세요 ▼▼▼
    try {
      return StudyGroupJoinRequest(
        requestId: json['request_id'],
        userId: json['user_id'],
        userName: json['user_name'],
        requestedAt: DateTime.parse(json['requested_at']),
      );
    } catch (e) {
      rethrow;
    }
    // ▲▲▲ 여기까지 추가 ▲▲▲
  }
}