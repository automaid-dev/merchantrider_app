import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/rider_providers.dart';
import 'rider_settlement_receipt_screen.dart';

/// List of every settlement (payout) this rider has ever received —
/// wraps POST /rider/settlement/list (Api/Rider/SettlementController::list).
/// Tapping a row opens the full receipt, viewable and downloadable as
/// a PDF.
class RiderSettlementListScreen extends ConsumerWidget {
  const RiderSettlementListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlementsAsync = ref.watch(riderSettlementListProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settlement History')),
      body: settlementsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load settlements.\n$e', textAlign: TextAlign.center)),
        data: (settlements) {
          if (settlements.isEmpty) {
            return const Center(child: Text('No settlements yet.'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(riderSettlementListProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: settlements.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final settlement = settlements[index];
                final netAmount = double.tryParse(settlement['net_amount']?.toString() ?? '') ?? 0;
                final paidAt = settlement['paid_at']?.toString();
                final hashslug = settlement['hashslug']?.toString();

                return Card(
                  child: ListTile(
                    leading: const Icon(Icons.receipt_long),
                    title: Text('RM${netAmount.toStringAsFixed(2)}',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    subtitle: Text([
                      if (paidAt != null) paidAt.split('T').first,
                      'Ref: ${settlement['bank_transaction_id'] ?? '-'}',
                    ].join('  ·  ')),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: hashslug == null
                        ? null
                        : () => Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RiderSettlementReceiptScreen(hashslug: hashslug),
                              ),
                            ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
