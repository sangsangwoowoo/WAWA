// lib/models/community_model.dart

class Post {
  final int id;
  final String title;
  final String content;
  final String userId;
  final String category;
  final DateTime createdAt;
  final String userName; // ▼▼▼ [추가] 작성자 이름을 저장할 필드 ▼▼▼

  Post({
    required this.id,
    required this.title,
    required this.content,
    required this.userId,
    required this.category,
    required this.createdAt,
    required this.userName, // ▼▼▼ [추가] 생성자에 추가 ▼▼▼
  });

  factory Post.fromJson(Map<String, dynamic> json) {
    // ▼▼▼ [수정] 중첩된 user_account 객체에서 name을 안전하게 추출 ▼▼▼
    final userName = (json['user_account'] != null && json['user_account']['name'] != null)
        ? json['user_account']['name'] as String
        : '알 수 없는 사용자';

    return Post(
      id: json['id'],
      title: json['title'] ?? '제목 없음',
      content: json['content'] ?? '내용 없음',
      userId: json['user_id'] ?? '',
      category: json['category'] ?? '자유게시판',
      createdAt: DateTime.parse(json['created_at']),
      userName: userName, // ▼▼▼ [추가] 추출한 이름을 할당 ▼▼▼
    );
  }
}

// ▼▼▼ [추가] 댓글 모델 클래스 ▼▼▼
class Comment {
  final int id;
  final String content;
  final String userId;
  final int postId;
  final DateTime createdAt;
  final String userName; // 👈 [추가]

  Comment({
    required this.id,
    required this.content,
    required this.userId,
    required this.postId,
    required this.createdAt,
    required this.userName, // 👈 [추가]
  });

  factory Comment.fromJson(Map<String, dynamic> json) {
    // 👈 [수정] 중첩된 user_account 객체에서 name을 안전하게 추출
    final userName = (json['user_account'] != null && json['user_account']['name'] != null)
        ? json['user_account']['name'] as String
        : '알 수 없는 사용자';

    return Comment(
      id: json['id'],
      content: json['content'] ?? '내용 없음',
      userId: json['user_id'] ?? '',
      postId: json['post_id'],
      createdAt: DateTime.parse(json['created_at']),
      userName: userName, // 👈 [추가]
    );
  }
}