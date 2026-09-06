import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../../../core/widgets/order_status_timeline.dart';
import '../providers/merchant_providers.dart';

/// Full order detail for a merchant's job — wraps POST /merchant/order/detail.
///
/// [id] + [isComplete] map directly to the backend's dual-purpose lookup:
/// pass an order_id with isComplete=true, or an assign_job id with
/// isComplete=false (matches Api/Merchant/OrderController::orderDetail).
class MerchantOrderDetailScreen extends ConsumerStatefulWidget {
  const MerchantOrderDetailScreen({super.key, required this.id, this.isComplete = false});
  final int id;
  final bool isComplete;

  @override
  ConsumerState<MerchantOrderDetailScreen> createState() => _MerchantOrderDetailScreenState();
}

class _MerchantOrderDetailScreenState extends ConsumerState<MerchantOrderDetailScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final repo = ref.read(merchantRepositoryProvider);
      final data = await repo.orderDetail(id: widget.id, isComplete: widget.isComplete);
      setState(() {
        _data = data;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  /// The order object regardless of which response shape `_data` is —
  /// itself directly when isComplete=true, or nested under 'order' when
  /// it's an assign_job (isComplete=false). Previously the tracking
  /// timeline only ever looked at the top-level 'merchant_order_statuses'
  /// key, which only exists in the isComplete=true shape — so every tap
  /// from the dashboard (which always passes isComplete=false) got a
  /// response that DID include the tracking data, just nested under
  /// 'order', and the screen never looked there.
  Map<String, dynamic>? get _order =>
      widget.isComplete ? _data : _data?['order'] as Map<String, dynamic>?;

  /// This merchant's own commission transaction for this order — the
  /// backend already scopes `commission_transactions` on the order
  /// detail response to this merchant's own Commission (see
  /// Api/Merchant/OrderController::orderDetail).
  Map<String, dynamic>? get _commissionTransaction {
    final transactions = _order?['commission_transactions'] as List<dynamic>?;
    if (transactions == null || transactions.isEmpty) return null;
    return transactions.first as Map<String, dynamic>;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Order detail')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text('Order ID: ${_data?['order_id'] ?? _data?['id'] ?? '-'}'),
                      Text('Status code: ${_data?['code'] ?? '-'}'),
                      if (_data?['quantity'] != null) Text('Bags: ${_data?['quantity']}'),
                      if (_commissionTransaction != null) ...[
                        const SizedBox(height: 8),
                        _CommissionStatusBadge(transaction: _commissionTransaction!),
                      ],
                      if (_order?['merchant_order_statuses'] != null) ...[
                        const Divider(height: 32),
                        Text('Order status', style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 12),
                        OrderStatusTimeline(statuses: _order!['merchant_order_statuses'] as List<dynamic>),
                      ],
                    ],
                  ),
                ),
    );
  }
}

/// Small "Settled" / "Pending" chip showing whether this order's
/// commission has actually been paid out yet, plus the amount — same
/// widget/reasoning as the rider order detail screen's version.
class _CommissionStatusBadge extends StatelessWidget {
  const _CommissionStatusBadge({required this.transaction});
  final Map<String, dynamic> transaction;

  @override
  Widget build(BuildContext context) {
    final amount = double.tryParse(transaction['final_amount']?.toString() ?? '') ?? 0;
    final isSettled = transaction['status']?.toString() == 'paid';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isSettled ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isSettled ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSettled ? Icons.check_circle_outline : Icons.schedule,
            size: 16,
            color: isSettled ? Colors.green.shade700 : Colors.orange.shade800,
          ),
          const SizedBox(width: 6),
          Text(
            'Commission RM${amount.toStringAsFixed(2)} — ${isSettled ? 'Settled' : 'Pending'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isSettled ? Colors.green.shade800 : Colors.orange.shade900,
            ),
          ),
        ],
      ),
    );
  }
}
