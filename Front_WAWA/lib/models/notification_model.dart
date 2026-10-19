import 'package:flutter/material.dart';

class Notification {
  final int id;
  final String userId;
  final String type;
  final String content;
  final bool isRead;
  final DateTime createdAt;

  Notification({
    required this.id,
    required this.userId,
    required this.type,
    required this.content,
    required this.isRead,
    required this.createdAt,
  });

  factory Notification.fromJson(Map<String, dynamic> json) {
    return Notification(
      id: json['id'],
      userId: json['user_id'],
      type: json['type'] ?? 'default',
      content: json['content'] ?? '내용 없음',
      isRead: json['is_read'] ?? false,
      createdAt: DateTime.parse(json['created_at']),
    );
  }

  // 아이콘 매핑을 위한 헬퍼 메소드
  IconData get icon {
    switch (type) {
      case 'start':
        return Icons.play_circle_outline;
      case 'progress':
        return Icons.trending_up;
      case 'review':
        return Icons.school_outlined;
      default:
        return Icons.notifications_none;
    }
  }
}