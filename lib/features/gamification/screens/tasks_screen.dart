import 'package:flutter/material.dart';

import '../models/task_item.dart';
import '../services/gamification_service.dart';
import 'package:srood_live/core/extensions/locale_extension.dart';
import 'package:srood_live/shared/widgets/srood_toast.dart';

class TasksScreen extends StatefulWidget {
  const TasksScreen({required this.isArabic, super.key});
  final bool isArabic;

  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen>
    with SingleTickerProviderStateMixin {
  final _service = const GamificationService();
  late final TabController _tab;

  List<TaskItem> _tasks = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await _service.getMyTasks();
      if (!mounted) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _claim(TaskItem task) async {
    try {
      await _service.claimTaskReward(task.id);
      if (!mounted) return;
      SroodToast.show(
        context,
        context.isArabic
            ? '\u062a\u0645 \u0627\u0633\u062a\u0644\u0627\u0645 ${_fmt(task.rewardAmount)} \u0639\u0645\u0644\u0629!'
            : '${_fmt(task.rewardAmount)} coins claimed!',
        type: SroodToastType.success,
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      SroodToast.show(context, e.toString(), type: SroodToastType.error);
    }
  }

  String _fmt(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF12061F), Color(0xFF07030D), Color(0xFF050208)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _buildHeader(),
              _buildTabBar(),
              Expanded(child: _buildBody()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
    child: Row(
      textDirection: context.isArabic ? TextDirection.rtl : TextDirection.ltr,
      children: [
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        ),
        Text(
          context.isArabic ? '\u0627\u0644\u0645\u0647\u0627\u0645' : 'Tasks',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    ),
  );

  Widget _buildTabBar() => Container(
    margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      color: const Color(0xFF1B102A),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFF4A3470)),
    ),
    child: TabBar(
      controller: _tab,
      indicator: BoxDecoration(
        color: const Color(0xFFF0C15A),
        borderRadius: BorderRadius.circular(10),
      ),
      indicatorSize: TabBarIndicatorSize.tab,
      labelColor: const Color(0xFF160B26),
      unselectedLabelColor: const Color(0xFFD8CFEA),
      labelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
      dividerColor: Colors.transparent,
      tabs: [
        Tab(text: context.isArabic ? '\u064a\u0648\u0645\u064a\u0629' : 'Daily'),
        Tab(
          text: context.isArabic
              ? '\u0623\u0633\u0628\u0648\u0639\u064a\u0629'
              : 'Weekly',
        ),
      ],
    ),
  );

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFFF0C15A),
          strokeWidth: 2.5,
        ),
      );
    }
    if (_error != null) return _buildError();

    final daily = _tasks.where((t) => t.isDaily).toList();
    final weekly = _tasks.where((t) => !t.isDaily).toList();

    return TabBarView(
      controller: _tab,
      children: [
        _TaskList(
          tasks: daily,
          isArabic: context.isArabic,
          onClaim: _claim,
          onRefresh: _load,
        ),
        _TaskList(
          tasks: weekly,
          isArabic: context.isArabic,
          onClaim: _claim,
          onRefresh: _load,
        ),
      ],
    );
  }

  Widget _buildError() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFFF5C7A),
          size: 40,
        ),
        const SizedBox(height: 12),
        Text(
          _error!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFFD8CFEA), fontSize: 13),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _load,
          child: Text(
            context.isArabic
                ? '\u0625\u0639\u0627\u062f\u0629 \u0627\u0644\u0645\u062d\u0627\u0648\u0644\u0629'
                : 'Retry',
            style: const TextStyle(color: Color(0xFFF0C15A)),
          ),
        ),
      ],
    ),
  );
}

// ---------------------------------------------------------------------------
// Task list
// ---------------------------------------------------------------------------

class _TaskList extends StatelessWidget {
  const _TaskList({
    required this.tasks,
    required this.isArabic,
    required this.onClaim,
    required this.onRefresh,
  });

  final List<TaskItem> tasks;
  final bool isArabic;
  final void Function(TaskItem) onClaim;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return Center(
        child: Text(
          isArabic
              ? '\u0644\u0627 \u062a\u0648\u062c\u062f \u0645\u0647\u0627\u0645'
              : 'No tasks',
          style: const TextStyle(color: Color(0xFF7A6890), fontSize: 15),
        ),
      );
    }
    return RefreshIndicator(
      color: const Color(0xFFF0C15A),
      backgroundColor: const Color(0xFF1B102A),
      onRefresh: onRefresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: tasks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 10),
        itemBuilder: (_, i) =>
            _TaskCard(task: tasks[i], isArabic: isArabic, onClaim: onClaim),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Task card
// ---------------------------------------------------------------------------

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    required this.task,
    required this.isArabic,
    required this.onClaim,
  });
  final TaskItem task;
  final bool isArabic;
  final void Function(TaskItem) onClaim;

  String _fmt(int n) {
    if (n >= 1000000) {
      return '${(n / 1000000).toStringAsFixed(n % 1000000 == 0 ? 0 : 1)}M';
    }
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}K';
    }
    return '$n';
  }

  @override
  Widget build(BuildContext context) {
    final progress = task.progressFraction;
    final canClaim = task.canClaim;
    final claimed = task.claimed;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12091D),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: canClaim
              ? const Color(0xFFF0C15A).withValues(alpha: 0.6)
              : claimed
              ? const Color(0xFF2ECC71).withValues(alpha: 0.3)
              : const Color(0xFF4A3470),
        ),
      ),
      child: Column(
        crossAxisAlignment: isArabic
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _iconBg(task.requirementType),
                ),
                child: Icon(
                  _taskIcon(task.requirementType),
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: isArabic
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.localTitle(isArabic),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      task.localDescription(isArabic),
                      style: const TextStyle(
                        color: Color(0xFF7A6890),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Reward badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0C15A).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: const Color(0xFFF0C15A).withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.monetization_on_rounded,
                      color: Color(0xFFF0C15A),
                      size: 13,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      _fmt(task.rewardAmount),
                      style: const TextStyle(
                        color: Color(0xFFF0C15A),
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Progress bar
          Column(
            crossAxisAlignment: isArabic
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              Row(
                textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isArabic
                        ? '${task.progress}/${task.requirementCount} \u0645\u0643\u062a\u0645\u0644'
                        : '${task.progress}/${task.requirementCount} done',
                    style: const TextStyle(
                      color: Color(0xFFD8CFEA),
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    '${(progress * 100).toInt()}%',
                    style: const TextStyle(
                      color: Color(0xFF7A6890),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: const Color(0xFF2D1A4A),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    claimed ? const Color(0xFF2ECC71) : const Color(0xFFF0C15A),
                  ),
                ),
              ),
            ],
          ),
          if (canClaim || claimed) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: claimed
                  ? Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2ECC71).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFF2ECC71).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        isArabic
                            ? '\u2713 \u062a\u0645 \u0627\u0644\u0627\u0633\u062a\u0644\u0627\u0645'
                            : '\u2713 Collected',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Color(0xFF2ECC71),
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    )
                  : ElevatedButton(
                      onPressed: () => onClaim(task),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF0C15A),
                        foregroundColor: const Color(0xFF160B26),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 0,
                      ),
                      child: Text(
                        isArabic
                            ? '\u0627\u0633\u062a\u0644\u0627\u0645 \u0627\u0644\u0645\u0643\u0627\u0641\u0623\u0629'
                            : 'Claim Reward',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _taskIcon(String type) => switch (type) {
    'send_gift' => Icons.card_giftcard_rounded,
    'join_room' => Icons.meeting_room_rounded,
    'send_message' => Icons.chat_bubble_rounded,
    'follow_user' => Icons.person_add_rounded,
    _ => Icons.task_alt_rounded,
  };

  Color _iconBg(String type) => switch (type) {
    'send_gift' => const Color(0xFF8B26D9),
    'join_room' => const Color(0xFF4B168C),
    'send_message' => const Color(0xFF2563EB),
    'follow_user' => const Color(0xFF0891B2),
    _ => const Color(0xFF374151),
  };
}
