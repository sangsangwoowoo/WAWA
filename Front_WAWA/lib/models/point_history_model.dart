// lib/models/point_history_model.dart

class PointTransaction {
  final int id;
  final DateTime createdAt;
  final int amount;
  final String reason;

  PointTransaction({
    required this.id,
    required this.createdAt,
    required this.amount,
    required this.reason,
  });

  factory PointTransaction.fromJson(Map<String, dynamic> json) {
    return PointTransaction(
      id: json['id'],
      createdAt: DateTime.parse(json['created_at']),
      // ▼▼▼ [핵심 수정] 'amount' 대신 'change_amount' 키에서 값을 가져옵니다. ▼▼▼
      amount: json['change_amount'],
      reason: json['reason'] ?? '내역 없음',
    );
  }
}