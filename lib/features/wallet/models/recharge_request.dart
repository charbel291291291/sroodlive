enum RechargeMethod { omt, wish, usdt, agent, cash, adminManual }

enum RechargeStatus { pending, approved, rejected, cancelled }

class RechargeRequest {
  const RechargeRequest({
    required this.id,
    required this.userId,
    required this.requestedCoins,
    required this.method,
    required this.status,
    this.publicUserId,
    this.requestedAmountUsd,
    this.referenceCode,
    this.agentCode,
    this.adminNote,
    this.rejectReason,
    this.createdAt,
    this.approvedAt,
    this.rejectedAt,
  });

  final String id;
  final String userId;
  final String? publicUserId;
  final int requestedCoins;
  final double? requestedAmountUsd;
  final RechargeMethod method;
  final RechargeStatus status;
  final String? referenceCode;
  final String? agentCode;
  final String? adminNote;
  final String? rejectReason;
  final DateTime? createdAt;
  final DateTime? approvedAt;
  final DateTime? rejectedAt;

  factory RechargeRequest.fromJson(Map<String, dynamic> json) {
    return RechargeRequest(
      id: json['id']?.toString() ?? '',
      userId: json['user_id']?.toString() ?? '',
      publicUserId: json['public_user_id']?.toString(),
      requestedCoins: _intValue(json['requested_coins']),
      requestedAmountUsd: _doubleValue(json['requested_amount_usd']),
      method: _methodFromKey(json['method']?.toString()),
      status: _statusFromKey(json['status']?.toString()),
      referenceCode: json['reference_code']?.toString(),
      agentCode: json['agent_code']?.toString(),
      adminNote: json['admin_note']?.toString(),
      rejectReason: json['reject_reason']?.toString(),
      createdAt: _dateValue(json['created_at']),
      approvedAt: _dateValue(json['approved_at']),
      rejectedAt: _dateValue(json['rejected_at']),
    );
  }

  String get methodLabel {
    return switch (method) {
      RechargeMethod.omt => 'OMT',
      RechargeMethod.wish => 'Wish',
      RechargeMethod.usdt => 'USDT',
      RechargeMethod.agent => 'Agent',
      RechargeMethod.cash => 'Cash',
      RechargeMethod.adminManual => 'Admin',
    };
  }

  String get statusLabel {
    return switch (status) {
      RechargeStatus.pending => 'Pending',
      RechargeStatus.approved => 'Approved',
      RechargeStatus.rejected => 'Rejected',
      RechargeStatus.cancelled => 'Cancelled',
    };
  }

  String get methodKey {
    return switch (method) {
      RechargeMethod.omt => 'omt',
      RechargeMethod.wish => 'wish',
      RechargeMethod.usdt => 'usdt',
      RechargeMethod.agent => 'agent',
      RechargeMethod.cash => 'cash',
      RechargeMethod.adminManual => 'admin_manual',
    };
  }

  static RechargeMethod _methodFromKey(String? key) {
    return switch (key) {
      'omt' => RechargeMethod.omt,
      'wish' => RechargeMethod.wish,
      'usdt' => RechargeMethod.usdt,
      'agent' => RechargeMethod.agent,
      'cash' => RechargeMethod.cash,
      'admin_manual' => RechargeMethod.adminManual,
      _ => RechargeMethod.omt,
    };
  }

  static RechargeStatus _statusFromKey(String? key) {
    return switch (key) {
      'approved' => RechargeStatus.approved,
      'rejected' => RechargeStatus.rejected,
      'cancelled' => RechargeStatus.cancelled,
      _ => RechargeStatus.pending,
    };
  }

  static int _intValue(dynamic value) {
    if (value is num) {
      return value.toInt();
    }

    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static double? _doubleValue(dynamic value) {
    if (value == null) {
      return null;
    }

    if (value is num) {
      return value.toDouble();
    }

    return double.tryParse(value.toString());
  }

  static DateTime? _dateValue(dynamic value) {
    if (value == null) {
      return null;
    }

    return DateTime.tryParse(value.toString());
  }
}
