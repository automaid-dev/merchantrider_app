import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'core/auth/auth_providers.dart';
import 'core/models/app_user.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'core/push/push_service.dart';
import 'features/merchant/notifications/merchant_notifications_screen.dart';
import 'features/merchant/providers/merchant_providers.dart';
import 'features/rider/notifications/rider_notifications_screen.dart';
import 'features/rider/providers/rider_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase Cloud Messaging push. Best-effort: never blocks app start.
  await PushService.instance.init();
  runApp(const ProviderScope(child: AutomaidPartnerApp()));
}

final _messengerKey = GlobalKey<ScaffoldMessengerState>();

/// "Partner" app: serves both rider and merchant (wash outlet) roles from
/// one codebase/one install — role decides which home screen shows after
/// login (see core/router/app_router.dart).
class AutomaidPartnerApp extends ConsumerStatefulWidget {
  const AutomaidPartnerApp({super.key});

  @override
  ConsumerState<AutomaidPartnerApp> createState() => _AutomaidPartnerAppState();
}

class _AutomaidPartnerAppState extends ConsumerState<AutomaidPartnerApp> {
  StreamSubscription<PushMessage>? _fgSub;
  StreamSubscription<PushMessage>? _openSub;

  UserRole? get _role {
    final auth = ref.read(authControllerProvider);
    if (auth.status != AuthStatus.authenticated) return null;
    final role = auth.user?.primaryRole;
    return (role == UserRole.rider || role == UserRole.merchant) ? role : null;
  }

  @override
  void initState() {
    super.initState();
    _fgSub = PushService.instance.foregroundMessages.listen(_onForeground);
    _openSub = PushService.instance.openedMessages.listen((_) => _openInbox());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (PushService.instance.takeLaunchMessage() != null) {
        // Wait for the session to be restored before opening the inbox.
        _openInboxWhenSignedIn();
      }
    });
  }

  @override
  void dispose() {
    _fgSub?.cancel();
    _openSub?.cancel();
    super.dispose();
  }

  /// New job offers and status changes arrive as pushes, so refresh the
  /// home job lists as well as the inbox.
  void _refreshLists(UserRole role) {
    if (role == UserRole.rider) {
      ref.invalidate(riderNotificationsProvider);
      ref.invalidate(riderHomeProvider);
    } else {
      ref.invalidate(merchantNotificationsProvider);
      ref.invalidate(merchantHomeProvider);
    }
  }

  /// Notification while the app is open: refresh lists and show a banner.
  void _onForeground(PushMessage m) {
    final role = _role;
    if (role == null) return;
    _refreshLists(role);
    final text = [m.title, m.body].where((s) => s.trim().isNotEmpty).join('\n');
    if (text.isEmpty) return;
    _messengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(text, maxLines: 3, overflow: TextOverflow.ellipsis),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 6),
        action: SnackBarAction(label: 'View', onPressed: _openInbox),
      ));
  }

  /// Tapped notification: open this role's notifications inbox.
  void _openInbox() {
    final role = _role;
    if (role == null) return;
    _refreshLists(role);
    final nav = ref.read(routerProvider).routerDelegate.navigatorKey.currentState;
    nav?.push(MaterialPageRoute(
      builder: (_) => role == UserRole.rider
          ? const RiderNotificationsScreen()
          : const MerchantNotificationsScreen(),
    ));
  }

  void _openInboxWhenSignedIn() {
    if (_role != null) {
      _openInbox();
      return;
    }
    late final ProviderSubscription<AuthState> sub;
    sub = ref.listenManual<AuthState>(authControllerProvider, (prev, next) {
      if (next.status == AuthStatus.authenticated) {
        sub.close();
        WidgetsBinding.instance.addPostFrameCallback((_) => _openInbox());
      } else if (next.status == AuthStatus.unauthenticated) {
        sub.close();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);

    return MaterialApp.router(
      title: 'LB AutoMaid Partner',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      scaffoldMessengerKey: _messengerKey,
      routerConfig: router,
    );
  }
}
