import 'package:flutter/material.dart';

/// Vertical status timeline for a rider or merchant order — renders
/// whatever `*_order_statuses` entries the backend returns (each with
/// `code`, `is_done`, `done_at`, and a nested `status.desc` title).
/// Mirrors the customer app's own status timeline so all three apps
/// show the same kind of "here's exactly where this order is" view,
/// just using each role's own more granular status codes.
class OrderStatusTimeline extends StatelessWidget {
  const OrderStatusTimeline({super.key, required this.statuses});
  final List<dynamic> statuses;

  /// Display order for the rider codes — deliberately NOT plain numeric
  /// order. Code 17 "awaiting wash to complete" is a parallel/waiting
  /// state that happens between the rider dropping off at the outlet
  /// (13) and picking the washed items back up (14), even though its
  /// numeric value sorts after everything else including "Order
  /// delivered" (16). Sorting by raw code string previously pushed it
  /// all the way to the end of the timeline, well past steps that
  /// haven't even happened yet — confusing since it's actually one of
  /// the earliest steps to complete. Any code not listed here (i.e.
  /// merchant codes, which are already in a sensible numeric order)
  /// falls back to its own natural position via the index lookup below.
  static const _riderDisplayOrder = ['11', '12', '13', '17', '14', '15', '16'];

  /// The fuller "what's actually happening at this step" copy — the
  /// backend's own status.desc is just a short title (e.g. "Ready for
  /// pickup"), so this is kept here rather than added as a backend
  /// column since it's static reference text, identical for every
  /// order, not order-specific data.
  static const _descriptions = {
    // Rider
    '11': 'You have a new booking request. Tap "Accept" to confirm the job.',
    '12': 'Order accepted. Head to customer location. Drive to customer, collect laundry, and verify bag tag.',
    '13': 'Laundry collected. En route to the wash facility. Deliver bag to facility staff and ask the staff to tap "Receive bag".',
    '17': 'Wash in progress at facility. Stand by or accept other nearby tasks while wash completes.',
    '14': 'Clean laundry is packed and ready for return. Collect packed order from outlet and confirm bag ID.',
    '15': "En route to customer's delivery address. Drive to customer location and notify them on arrival.",
    '16': 'Order delivered to customer. Hand over laundry, confirm drop-off, and close job.',
    // Merchant
    '21': 'New order incoming from platform. Tap "Accept Order" to confirm facility capacity.',
    '22': "Rider is en route with customer's dirty laundry. Prepare intake bay and intake tags.",
    '23': 'Laundry received and checked in. Sort, wash, dry, fold, and quality-check items.',
    '24': 'Order packed and ready for outbound rider. Stage bagged laundry in pickup area and mark "Ready."',
    '25': 'Rider collected package and heading to customer. Hand over order to rider and log handover ID.',
    '26': 'Order successfully delivered to customer. Archive order and automatically close job.',
  };

  int _sortKey(String code) {
    final i = _riderDisplayOrder.indexOf(code);
    // Not one of the rider codes (e.g. a merchant code) — keep it in
    // its own natural numeric position by using the code itself,
    // offset well past the rider range so it never interleaves.
    return i != -1 ? i : 100 + (int.tryParse(code) ?? 0);
  }

  /// Formats an ISO timestamp like "21 Aug 2026, 3:05 AM" — matches the
  /// same hand-rolled style already used on the dashboard banner
  /// elsewhere in this app, rather than introducing a different date
  /// format in just this one place.
  static String? _formatDate(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return null;
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final period = dt.hour < 12 ? 'AM' : 'PM';
    final minute = dt.minute.toString().padLeft(2, '0');
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}, $hour12:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final entries = statuses.cast<Map<String, dynamic>>().toList()
      ..sort((a, b) => _sortKey(a['code']?.toString() ?? '').compareTo(_sortKey(b['code']?.toString() ?? '')));

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
            description: _descriptions[entries[i]['code']?.toString()],
            isDone: entries[i]['is_done'] == true || entries[i]['is_done'] == 1,
            doneAt: _formatDate(entries[i]['done_at']?.toString()),
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
    this.description,
    this.doneAt,
  });
  final String title;
  final String? description;
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
                  if (description != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      description!,
                      style: TextStyle(fontSize: 13, color: isDone ? Colors.grey[700] : Colors.grey[500]),
                    ),
                  ],
                  if (isDone && doneAt != null) ...[
                    const SizedBox(height: 4),
                    Text('Completed on: $doneAt', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

