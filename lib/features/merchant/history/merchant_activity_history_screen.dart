import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/merchant_providers.dart';

/// Every activity this merchant has been part of, newest first — including
/// jobs an admin cancelled, which previously just vanished from the
/// dashboard with no record anywhere in the app at all.
class MerchantActivityHistoryScreen extends ConsumerWidget {
  const MerchantActivityHistoryScreen({super.key});

  bool _isCancelled(String title) => title.toLowerCase().contains('cancel');

  IconData _iconFor(String title) {
    final lower = title.toLowerCase();
    if (_isCancelled(lower)) return Icons.cancel_outlined;
    if (lower.contains('deliver')) return Icons.local_shipping_outlined;
    if (lower.contains('pickup') || lower.contains('pick up')) return Icons.inventory_2_outlined;
    if (lower.contains('wash')) return Icons.local_laundry_service_outlined;
    return Icons.history;
  }

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(merchantActivityHistoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Activity history')),
      body: activitiesAsync.when(
        data: (activities) => activities.isEmpty
            ? const Center(child: Text('No activity yet.'))
            : RefreshIndicator(
                onRefresh: () async => ref.invalidate(merchantActivityHistoryProvider),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: activities.length,
                  itemBuilder: (context, i) {
                    final a = activities[i];
                    final title = a['title']?.toString() ?? 'Update';
                    final cancelled = _isCancelled(title);
                    final order = a['order'] as Map<String, dynamic>?;
                    final createdAt = DateTime.tryParse(a['created_at']?.toString() ?? '');

                    return ListTile(
                      leading: Icon(_iconFor(title), color: cancelled ? Colors.red : null),
                      title: Text(
                        title,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: cancelled ? Colors.red : null,
                        ),
                      ),
                      subtitle: Text('Order #${order?['id'] ?? a['order_id'] ?? '-'}'),
                      trailing: Text(_timeAgo(createdAt), style: const TextStyle(fontSize: 12)),
                    );
                  },
                ),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load activity history: $e')),
      ),
    );
  }
}
