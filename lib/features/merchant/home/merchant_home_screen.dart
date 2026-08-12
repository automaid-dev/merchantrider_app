import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/auth/auth_providers.dart';

/// Placeholder landing screen for the merchant (wash outlet) role.
/// Next up here (per POST /merchant/home + /merchant/home/city): duty +
/// city selection, incoming bag list, wash-complete flow entry points.
class MerchantHomeScreen extends ConsumerWidget {
  const MerchantHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    return Scaffold(
      appBar: AppBar(
        title: Text('Merchant — ${user?.name ?? ''}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
          ),
        ],
      ),
      body: const Center(child: Text('Merchant home — incoming bags, wash-complete go here')),
    );
  }
}
