// lib/models/attendance_model.dart

class AttendanceRecord {
  final int id;
  final String userId;
  final DateTime date; // 백엔드에서 date 타입이 ISO 8601 문자열로 오므로 DateTime으로 파싱

  AttendanceRecord({required this.id, required this.userId, required this.date});

  factory AttendanceRecord.fromJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      id: json['id'],
      userId: json['user_id'],
      date: DateTime.parse(json['date']),
    );
  }
}

class AttendanceStats {
  final int totalDays;
  final int longestStreak;

  AttendanceStats({required this.totalDays, required this.longestStreak});

  factory AttendanceStats.fromJson(Map<String, dynamic> json) {
    return AttendanceStats(
      totalDays: json['total_days'],
      longestStreak: json['longest_streak'],
    );
  }
}