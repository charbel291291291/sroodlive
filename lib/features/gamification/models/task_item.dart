class TaskItem {
  const TaskItem({
    required this.id,
    required this.title,
    required this.titleAr,
    required this.description,
    required this.descriptionAr,
    required this.taskType,
    required this.requirementType,
    required this.requirementCount,
    required this.rewardType,
    required this.rewardAmount,
    required this.sortOrder,
    required this.progress,
    required this.completed,
    required this.claimed,
    this.completedAt,
  });

  factory TaskItem.fromJson(Map<String, dynamic> json) => TaskItem(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        titleAr: json['title_ar']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        descriptionAr: json['description_ar']?.toString() ?? '',
        taskType: json['task_type']?.toString() ?? 'daily',
        requirementType: json['requirement_type']?.toString() ?? '',
        requirementCount: (json['requirement_count'] as num?)?.toInt() ?? 1,
        rewardType: json['reward_type']?.toString() ?? 'coins',
        rewardAmount: (json['reward_amount'] as num?)?.toInt() ?? 0,
        sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
        progress: (json['progress'] as num?)?.toInt() ?? 0,
        completed: json['completed'] == true,
        claimed: json['claimed'] == true,
        completedAt: DateTime.tryParse(json['completed_at']?.toString() ?? ''),
      );

  final String id;
  final String title;
  final String titleAr;
  final String description;
  final String descriptionAr;
  final String taskType;
  final String requirementType;
  final int requirementCount;
  final String rewardType;
  final int rewardAmount;
  final int sortOrder;
  final int progress;
  final bool completed;
  final bool claimed;
  final DateTime? completedAt;

  bool get isDaily => taskType == 'daily';
  bool get canClaim => completed && !claimed;

  double get progressFraction =>
      requirementCount > 0 ? (progress / requirementCount).clamp(0.0, 1.0) : 0.0;

  String localTitle(bool isArabic) => isArabic && titleAr.isNotEmpty ? titleAr : title;
  String localDescription(bool isArabic) =>
      isArabic && descriptionAr.isNotEmpty ? descriptionAr : description;
}
