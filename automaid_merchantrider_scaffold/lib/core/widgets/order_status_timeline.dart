import 'package:flutter/material.dart';

/// Vertical status timeline for a rider or merchant order — renders
/// whatever `*_order_statuses` entries the backend returns (each with
/// `code`, `is_done`, and a nested `status.desc` description), sorted
/// by code. Mirrors the customer app's own status timeline so all three
/// apps show the same kind of "here's exactly where this order is"
/// view, just using each role's own more granular status codes.
class OrderStatusTimeline extends StatelessWidget {
  const OrderStatusTimeline({super.key, required this.statuses});
  final List<dynamic> statuses;

  @override
  Widget build(BuildContext context) {
    final entries = statuses.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => (a['code']?.toString() ?? '').compareTo(b['code']?.toString() ?? ''));

    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Text('No status updates yet.'),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < entries.length; i++)
          _TimelineTile(
            title: (entries[i]['status'] as Map<String, dynamic>?)?['desc']?.toString() ??
                'Status ${entries[i]['code']}',
            isDone: entries[i]['is_done'] == true || entries[i]['is_done'] == 1,
            doneAt: entries[i]['done_at']?.toString(),
            isLast: i == entries.length - 1,
          ),
      ],
    );
  }
}

class _TimelineTile extends StatelessWidget {
  const _TimelineTile({
    required this.title,
    required this.isDone,
    required this.isLast,
    this.doneAt,
  });
  final String title;
  final bool isDone;
  final bool isLast;
  final String? doneAt;

  @override
  Widget build(BuildContext context) {
    final color = isDone ? Theme.of(context).colorScheme.primary : Colors.grey.shade400;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Icon(isDone ? Icons.check_circle : Icons.circle_outlined, color: color, size: 20),
              if (!isLast) Expanded(child: Container(width: 2, color: color.withValues(alpha: 0.4))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: isDone ? null : Colors.grey)),
                  if (isDone && doneAt != null)
                    Text(doneAt!, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
