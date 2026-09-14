import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'register_rider_screen.dart';
import 'register_merchant_screen.dart';
import '../../core/widgets/need_help_button.dart';

enum _Role { rider, merchant }

/// Step 1/3 — "Which one describes you the best?" — matches the flow
/// spec exactly: rider splits into Gig Worker / Staff from Auto Maid,
/// merchant splits into Outlet Partner / Auto Maid Outlet. The chosen
/// type is passed straight into the role-specific registration screen
/// rather than carried as separate app state.
class RegisterRoleScreen extends StatefulWidget {
  const RegisterRoleScreen({super.key});

  @override
  State<RegisterRoleScreen> createState() => _RegisterRoleScreenState();
}

class _RegisterRoleScreenState extends State<RegisterRoleScreen> {
  _Role _role = _Role.rider;
  String? _riderType; // 'gig' | 'staff'
  String? _merchantType; // 'outlet_partner' | 'automaid_outlet'
  bool _agreedToTerms = false;

  // Note: the domain used here is lbunlimitedwash.com, matching every
  // other policy link already in this app/the customer app — the
  // domain as given in this request appeared to be a typo (missing
  // the 's' in "wash").
  late final _privacyNoticeRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/privacy_notice.html');
  late final _termsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/general_terms.html');

  @override
  void dispose() {
    _privacyNoticeRecognizer.dispose();
    _termsRecognizer.dispose();
    super.dispose();
  }

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  bool get _canContinue =>
      (_role == _Role.rider ? _riderType != null : _merchantType != null) && _agreedToTerms;

  void _continue() {
    if (!_canContinue) return;
    if (_role == _Role.rider) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RegisterRiderScreen(typeRider: _riderType!)),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RegisterMerchantScreen(typeMerchant: _merchantType!)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Step 1/3'),
        actions: const [NeedHelpButton()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Scrollable — this screen now has enough content (role
            // cards, type options, consent text) that it could overflow
            // on shorter devices otherwise, the same class of bug fixed
            // on the onboarding screen previously. The Next button below
            // stays pinned outside the scroll area.
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
            Text('Register to Get Started', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            const Text('Join our team and unlock new opportunities.'),
            const SizedBox(height: 24),
            const Text('Which one describes you the best?', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _RoleCard(
                    imageAsset: 'assets/images/mascot_rider.png',
                    label: "I'm a rider",
                    selected: _role == _Role.rider,
                    onTap: () => setState(() => _role = _Role.rider),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _RoleCard(
                    imageAsset: 'assets/images/mascot_merchant.png',
                    label: "I'm a merchant / laundry assistant",
                    selected: _role == _Role.merchant,
                    onTap: () => setState(() => _role = _Role.merchant),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_role == _Role.rider) ...[
              const Text('Type of Rider', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _OptionTile(
                label: 'Gig Worker',
                selected: _riderType == 'gig',
                onTap: () => setState(() => _riderType = 'gig'),
              ),
              _OptionTile(
                label: 'Staff from Auto Maid',
                selected: _riderType == 'staff',
                onTap: () => setState(() => _riderType = 'staff'),
              ),
            ] else ...[
              const Text('Type of Merchant', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              _OptionTile(
                label: 'Outlet Partner',
                selected: _merchantType == 'outlet_partner',
                onTap: () => setState(() => _merchantType = 'outlet_partner'),
              ),
              _OptionTile(
                label: 'Auto Maid Outlet',
                selected: _merchantType == 'automaid_outlet',
                onTap: () => setState(() => _merchantType = 'automaid_outlet'),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _agreedToTerms,
                  onChanged: (v) => setState(() => _agreedToTerms = v ?? false),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: RichText(
                      text: TextSpan(
                        style: TextStyle(fontSize: 12.5, color: Colors.grey[700], height: 1.4),
                        children: [
                          const TextSpan(
                            text: 'By proceeding, I agree that LB Pickup and Delivery can '
                                'collect, use and disclose the information provided by me '
                                'in accordance with the ',
                          ),
                          TextSpan(
                            text: 'Privacy Notice',
                            style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            recognizer: _privacyNoticeRecognizer,
                          ),
                          const TextSpan(text: ' and I fully comply with '),
                          TextSpan(
                            text: 'Terms & Conditions',
                            style: const TextStyle(fontWeight: FontWeight.bold, decoration: TextDecoration.underline),
                            recognizer: _termsRecognizer,
                          ),
                          const TextSpan(text: ' which I have read and understand.'),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _canContinue ? _continue : null,
                child: const Text('Next'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({required this.imageAsset, required this.label, required this.selected, required this.onTap});
  final String imageAsset;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: selected ? scheme.primaryContainer : null,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.asset(
                  imageAsset,
                  height: 72,
                  width: 72,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 10),
              Text(label, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  const _OptionTile({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: RadioListTile<bool>(
        value: true,
        groupValue: selected ? true : null,
        onChanged: (_) => onTap(),
        title: Text(label),
      ),
    );
  }
}
