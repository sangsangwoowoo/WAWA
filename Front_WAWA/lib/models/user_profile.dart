class UserProfile {
  final String id;
  final String email;
  final bool isAdmin;
  final Map<String, dynamic> userMetadata;

  UserProfile({
    required this.id,
    required this.email,
    required this.userMetadata,
    required this.isAdmin,
  });

  // 편의 getter들
  String get name => userMetadata['name'] ?? '';
  String get level => userMetadata['level'] ?? '';

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['user_id'] ?? json['id'] ?? 'Unknown ID',
      email: json['email'] ?? 'No email provided',
      // ▼▼▼ [수정] 다양한 필드명에 대응 ▼▼▼
      isAdmin: json['isAdmin'] ?? json['is_admin'] ?? false,
      userMetadata: Map<String, dynamic>.from(json['user_metadata'] ?? {}),
    );
  }
}