import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/models/app_user.dart';
import '../../core/widgets/confirm_dialog.dart';

/// Shown when the account is authenticated (OTP verified) but the
/// Rider/Merchant entity itself hasn't been approved by admin yet —
/// matches AppUser.isPendingApproval (User.status == 'onboarding').
/// Matches the flow spec's "Application under Review" state exactly.
class PendingApprovalScreen extends ConsumerWidget {
  const PendingApprovalScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final mascotAsset = user?.primaryRole == UserRole.merchant
        ? 'assets/images/mascot_merchant.png'
        : 'assets/images/mascot_rider.png';

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(mascotAsset, height: 160),
              const SizedBox(height: 24),
              Text(
                'Application under Review',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              const Text(
                'Your application is currently undergoing review and verification.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Please wait for WhatsApp/SMS notification to activate your account.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              OutlinedButton(
                onPressed: () async {
                  final confirmed = await showLogoutConfirmDialog(context);
                  if (confirmed) {
                    ref.read(authControllerProvider.notifier).logout();
                  }
                },
                child: const Text('Logout'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
