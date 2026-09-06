import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:printing/printing.dart';
import '../providers/merchant_providers.dart';
import '../../../core/models/setting_model.dart';
import '../../../core/widgets/receipt_pdf.dart';

/// Full breakdown of one settlement (payout) — wraps POST
/// /merchant/settlement/detail (Api/Merchant/SettlementController::detail).
/// The download button builds a PDF client-side from the same data
/// already shown on screen, then hands it to the OS share/save sheet.
class MerchantSettlementReceiptScreen extends ConsumerWidget {
  const MerchantSettlementReceiptScreen({super.key, required this.hashslug});
  final String hashslug;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settlementAsync = ref.watch(merchantSettlementDetailProvider(hashslug));
    final settingAsync = ref.watch(merchantSettingProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settlement Receipt'),
        actions: [
          settlementAsync.maybeWhen(
            data: (settlement) => IconButton(
              icon: const Icon(Icons.download_outlined),
              tooltip: 'Download / share receipt',
              onPressed: () => _downloadReceipt(context, ref, settlement),
            ),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: settlementAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load receipt.\n$e', textAlign: TextAlign.center)),
        data: (settlement) => _ReceiptBody(
          settlement: settlement,
          setting: settingAsync.asData?.value,
        ),
      ),
    );
  }

  Future<void> _downloadReceipt(BuildContext context, WidgetRef ref, Map<String, dynamic> settlement) async {
    final setting = await ref.read(merchantRepositoryProvider).setting();
    final letterhead = ReceiptLetterhead(
      companyName: setting.companyName,
      companyAddress: setting.companyAddress,
      companyPhone: setting.companyPhone,
      companyEmail: setting.companyEmail,
      companyRegistrationNo: setting.companyRegistrationNo,
    );
    final rows = _buildRows(settlement);
    final bytes = await buildReceiptPdf(
      title: 'Settlement Receipt',
      rows: rows,
      footerNote: 'Thank you for partnering with Automaid.',
      letterhead: letterhead,
    );
    if (!context.mounted) return;
    await Printing.sharePdf(bytes: bytes, filename: 'automaid_settlement_${settlement['hashslug']}.pdf');
  }
}

List<MapEntry<String, String>> _buildRows(Map<String, dynamic> settlement) {
  final deductions = (settlement['deductions'] as List<dynamic>? ?? []);
  final transactions = (settlement['transactions'] as List<dynamic>? ?? []);
  final gross = double.tryParse(settlement['gross_amount']?.toString() ?? '') ?? 0;
  final totalDeductions = double.tryParse(settlement['total_deductions']?.toString() ?? '') ?? 0;
  final net = double.tryParse(settlement['net_amount']?.toString() ?? '') ?? 0;
  final paidAt = settlement['paid_at']?.toString();

  return [
    MapEntry('Paid at', paidAt != null ? paidAt.split('T').first : '-'),
    MapEntry('Bank / transfer reference', settlement['bank_transaction_id']?.toString() ?? '-'),
    MapEntry('Orders covered', '${transactions.length}'),
    MapEntry('Gross amount', 'RM${gross.toStringAsFixed(2)}'),
    for (final d in deductions)
      MapEntry(
        '${(d as Map<String, dynamic>)['type']?.toString().toUpperCase() ?? 'Deduction'}${d['description'] != null ? ' (${d['description']})' : ''}',
        '-RM${(double.tryParse(d['amount']?.toString() ?? '') ?? 0).toStringAsFixed(2)}',
      ),
    if (totalDeductions > 0) MapEntry('Total deductions', '-RM${totalDeductions.toStringAsFixed(2)}'),
    MapEntry('Net paid', 'RM${net.toStringAsFixed(2)}'),
    if (settlement['notes'] != null && settlement['notes'].toString().isNotEmpty)
      MapEntry('Notes', settlement['notes'].toString()),
  ];
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({required this.settlement, this.setting});
  final Map<String, dynamic> settlement;
  final AppSetting? setting;

  @override
  Widget build(BuildContext context) {
    final deductions = (settlement['deductions'] as List<dynamic>? ?? []);
    final transactions = (settlement['transactions'] as List<dynamic>? ?? []);
    final gross = double.tryParse(settlement['gross_amount']?.toString() ?? '') ?? 0;
    final totalDeductions = double.tryParse(settlement['total_deductions']?.toString() ?? '') ?? 0;
    final net = double.tryParse(settlement['net_amount']?.toString() ?? '') ?? 0;
    final paidAt = settlement['paid_at']?.toString();

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (setting != null) _Letterhead(setting: setting!),
                Icon(Icons.receipt_long, size: 48, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 8),
                const Text('Settlement receipt',
                    textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const Divider(height: 32),
                _Row(label: 'Paid at', value: paidAt != null ? paidAt.split('T').first : '-'),
                _Row(label: 'Bank / transfer reference', value: settlement['bank_transaction_id']?.toString() ?? '-'),
                _Row(label: 'Orders covered', value: '${transactions.length}'),
                const Divider(height: 32),
                _Row(label: 'Gross amount', value: 'RM${gross.toStringAsFixed(2)}'),
                if (deductions.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Deductions', style: Theme.of(context).textTheme.titleSmall),
                  ...deductions.map((d) {
                    final deduction = d as Map<String, dynamic>;
                    final amount = double.tryParse(deduction['amount']?.toString() ?? '') ?? 0;
                    return _Row(
                      label: [
                        deduction['type']?.toString(),
                        if (deduction['description'] != null) '(${deduction['description']})',
                      ].where((v) => v != null).join(' '),
                      value: '-RM${amount.toStringAsFixed(2)}',
                    );
                  }),
                  _Row(label: 'Total deductions', value: '-RM${totalDeductions.toStringAsFixed(2)}'),
                ],
                const Divider(height: 32),
                _Row(label: 'Net paid', value: 'RM${net.toStringAsFixed(2)}', emphasize: true),
                if (settlement['notes'] != null && settlement['notes'].toString().isNotEmpty) ...[
                  const Divider(height: 32),
                  Text('Notes', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  Text(settlement['notes'].toString()),
                ],
                if (transactions.isNotEmpty) ...[
                  const Divider(height: 32),
                  Text('Orders in this settlement', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 4),
                  ...transactions.map((t) {
                    final txn = t as Map<String, dynamic>;
                    final order = txn['order'] as Map<String, dynamic>?;
                    final amount = double.tryParse(txn['final_amount']?.toString() ?? '') ?? 0;
                    return _Row(label: 'Order #${order?['id'] ?? txn['order_id'] ?? '-'}', value: 'RM${amount.toStringAsFixed(2)}');
                  }),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.label, required this.value, this.emphasize = false});
  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
        : const TextStyle(fontSize: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: style.copyWith(color: emphasize ? null : Colors.grey[700]))),
          Text(value, style: style),
        ],
      ),
    );
  }
}

/// Company name/address/phone/email letterhead shown at the top of the
/// on-screen receipt — same as the rider version.
class _Letterhead extends StatelessWidget {
  const _Letterhead({required this.setting});
  final AppSetting setting;

  @override
  Widget build(BuildContext context) {
    final hasInfo = setting.companyName != null ||
        setting.companyAddress != null ||
        setting.companyPhone != null ||
        setting.companyEmail != null;
    if (!hasInfo) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (setting.companyName != null)
            Text(
              setting.companyName!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          if (setting.companyAddress != null)
            Text(
              setting.companyAddress!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
          if (setting.companyPhone != null || setting.companyEmail != null)
            Text(
              [setting.companyPhone, setting.companyEmail].where((v) => v != null).join('  ·  '),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11, color: Colors.grey[700]),
            ),
        ],
      ),
    );
  }
}
