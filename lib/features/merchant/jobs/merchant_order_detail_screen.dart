import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
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
                    ],
                  ),
                ),
    );
  }
}
