import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_client.dart';
import '../providers/rider_providers.dart';
import 'rider_profile_edit_screen.dart';

/// Wraps POST /rider/profile (RiderProfileController::profile), which
/// eager-loads wallet.transactions and activities. Tap the edit icon to
/// update profile fields (name, IC, address, emergency contact, bank
/// info + avatar) via RiderProfileEditScreen.
class RiderProfileScreen extends ConsumerStatefulWidget {
  const RiderProfileScreen({super.key});

  @override
  ConsumerState<RiderProfileScreen> createState() => _RiderProfileScreenState();
}

class _RiderProfileScreenState extends ConsumerState<RiderProfileScreen> {
  Map<String, dynamic>? _user;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final user = await ref.read(riderRepositoryProvider).profile();
      setState(() {
        _user = user;
        _loading = false;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e.message;
        _loading = false;
      });
    }
  }

  double _pendingAmount(Map<String, dynamic>? wallet) =>
      double.tryParse(wallet?['pending_settlement']?.toString() ?? '') ?? 0;

  String _formatAmount(dynamic value) {
    final parsed = double.tryParse(value?.toString() ?? '') ?? 0;
    return parsed.toStringAsFixed(2);
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _user?['wallet'] as Map<String, dynamic>?;
    final activities = (_user?['activities'] as List<dynamic>? ?? []);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My profile'),
        actions: [
          if (_user != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => RiderProfileEditScreen(initialUser: _user!)),
                );
                _load();
              },
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    Text(_user?['name']?.toString() ?? '-',
                        style: Theme.of(context).textTheme.titleLarge),
                    Text(_user?['email']?.toString() ?? '-'),
                    Text(_user?['mobile_no']?.toString() ?? '-'),
                    const Divider(height: 32),
                    // Two separate figures now, rather than the one
                    // ever-growing "Wallet balance" — that number was
                    // actually lifetime earnings the whole time (it
                    // never decreased even after admin settled a
                    // payout), with nothing distinguishing "already
                    // paid out" from "still owed". Both come straight
                    // from Commission::lifetime_earnings/
                    // pending_settlement on the backend, computed
                    // there rather than summed here from the raw
                    // transaction list.
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Lifetime earnings', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text(
                                'RM${_formatAmount(wallet?['lifetime_earnings'])}',
                                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Pending settlement', style: Theme.of(context).textTheme.titleSmall),
                              const SizedBox(height: 4),
                              Text(
                                'RM${_formatAmount(wallet?['pending_settlement'])}',
                                style: TextStyle(
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                  color: _pendingAmount(wallet) > 0 ? Colors.orange[800] : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 32),
                    Text('Recent activity', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 8),
                    if (activities.isEmpty)
                      const Text('No activity yet.')
                    else
                      ...activities.map((a) {
                        final activity = a as Map<String, dynamic>;
                        // Sum of this user's own commission transactions
                        // for this activity's order — typically just one
                        // row, but summed defensively in case more than
                        // one was ever recorded for the same order.
                        final order = activity['order'] as Map<String, dynamic>?;
                        final transactions = (order?['commission_transactions'] as List<dynamic>? ?? []);
                        final commission = transactions.fold<double>(
                          0,
                          (sum, t) => sum + (double.tryParse((t as Map<String, dynamic>)['final_amount']?.toString() ?? '') ?? 0),
                        );
                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            title: Text(activity['title']?.toString() ?? '-'),
                            subtitle: Text('Order #${activity['order_id'] ?? '-'}'),
                            trailing: commission > 0
                                ? Text(
                                    '+RM${commission.toStringAsFixed(2)}',
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                  )
                                : null,
                          ),
                        );
                      }),
                  ],
                ),
    );
  }
}
