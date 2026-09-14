import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// "Need Help?" text button meant to sit in an AppBar's `actions`
/// (top-right) — opens the help page in an in-app browser view rather
/// than leaving the app entirely.
class NeedHelpButton extends StatelessWidget {
  const NeedHelpButton({super.key});

  static const _url = 'https://lbunlimitedwash.com/help/become_rider.html';

  Future<void> _openHelp() async {
    final uri = Uri.parse(_url);
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _openHelp,
      child: const Text('Need Help?'),
    );
  }
}
