import 'dart:io';

import 'package:dio/dio.dart' show FormData, MultipartFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/models/app_user.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/confirm_dialog.dart';
import '../../core/widgets/delete_account_screen.dart';

/// Shown when admin rejected the rider/merchant registration
/// (User.status == 'rejected'). Lists what was wrong and lets the
/// applicant retake/upload only the photos admin asked for, plus the
/// licence / JPJ grant expiry date where relevant. After submitting, the
/// account goes back to "onboarding" and the router shows the
/// "Application under Review" screen until admin approves.
///
/// Backend: POST /profile/resubmission and /profile/resubmission/submit
/// (ResubmissionController).
class ResubmitDocumentsScreen extends ConsumerStatefulWidget {
  const ResubmitDocumentsScreen({super.key});

  @override
  ConsumerState<ResubmitDocumentsScreen> createState() => _ResubmitDocumentsScreenState();
}

class _ResubmitDocumentsScreenState extends ConsumerState<ResubmitDocumentsScreen> {
  static const _supportHotline = '1300820018';
  static const _supportHotlineLabel = '1-300-82-0018';

  bool _loading = true;
  bool _submitting = false;
  String? _loadError;
  String? _submitError;
  Map<String, dynamic>? _data;

  final Map<String, File> _newPhotos = {};
  final Map<String, DateTime> _expiry = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      final res = await ref.read(apiClientProvider).post(ApiEndpoints.profileResubmission);
      if (res['status'] == true) {
        _data = (res['data'] as Map).cast<String, dynamic>();
        // Pre-fill expiry dates already on record.
        for (final f in _expiryFields) {
          final current = DateTime.tryParse(f['current']?.toString() ?? '');
          if (current != null) _expiry[f['key'].toString()] = current;
        }
      } else {
        // Not rejected any more (e.g. admin already changed it) — refresh
        // the user so the router moves to the right screen.
        await _refreshUser();
        _loadError = res['message']?.toString();
      }
    } on ApiException catch (e) {
      _loadError = e.message;
    } catch (_) {
      _loadError = 'Could not load your application. Please try again.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _refreshUser() async {
    try {
      final me = await ref.read(apiClientProvider).post(ApiEndpoints.profileMe);
      final current = ref.read(authControllerProvider).user;
      final user = AppUser.fromJson(me);
      // /profile/me may not include roles; keep the ones we already know.
      ref.read(authControllerProvider.notifier).updateUser(
            user.roles.isEmpty && current != null
                ? AppUser(
                    id: user.id,
                    name: user.name,
                    email: user.email,
                    status: user.status,
                    isActive: user.isActive,
                    countryCodeMobile: user.countryCodeMobile,
                    mobileNo: user.mobileNo,
                    avatarUrl: user.avatarUrl,
                    roles: current.roles,
                  )
                : user,
          );
    } catch (_) {}
  }

  List<Map<String, dynamic>> get _documents =>
      ((_data?['documents'] as List?) ?? []).map((d) => (d as Map).cast<String, dynamic>()).toList();

  List<Map<String, dynamic>> get _expiryFields =>
      ((_data?['expiry_fields'] as List?) ?? []).map((d) => (d as Map).cast<String, dynamic>()).toList();

  int get _minDays => (_data?['min_days_valid'] as num?)?.toInt() ?? 14;

  DateTime get _minExpiry {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day).add(Duration(days: _minDays));
  }

  List<String> get _missing {
    final missing = <String>[];
    for (final d in _documents) {
      if (!_newPhotos.containsKey(d['key'])) missing.add('New photo: ${d['label']}');
    }
    for (final f in _expiryFields) {
      final key = f['key'].toString();
      final date = _expiry[key];
      if (f['required'] == true && date == null) missing.add(f['label'].toString());
      if (date != null && date.isBefore(_minExpiry)) {
        missing.add('${f['label']} must be at least $_minDays days from today');
      }
    }
    return missing;
  }

  Future<void> _pickPhoto(String key) async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('Take a photo'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) return;
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 85, maxWidth: 2400);
    if (picked != null && mounted) {
      setState(() {
        _newPhotos[key] = File(picked.path);
        _submitError = null;
      });
    }
  }

  Future<void> _pickDate(String key) async {
    final initial = _expiry[key] ?? _minExpiry;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(DateTime(2000)) ? _minExpiry : initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(DateTime.now().year + 15),
      helpText: 'Expiry date shown on the document',
    );
    if (picked != null && mounted) {
      setState(() {
        _expiry[key] = picked;
        _submitError = null;
      });
    }
  }

  Future<void> _submit() async {
    final missing = _missing;
    if (missing.isNotEmpty) {
      setState(() => _submitError = 'Please complete:\n• ${missing.join('\n• ')}');
      return;
    }
    setState(() {
      _submitting = true;
      _submitError = null;
    });
    try {
      final fmt = DateFormat('yyyy-MM-dd');
      final form = FormData.fromMap({
        for (final e in _newPhotos.entries)
          e.key: await MultipartFile.fromFile(e.value.path, filename: '${e.key}.jpg'),
        for (final e in _expiry.entries) e.key: fmt.format(e.value),
      });
      final res = await ref.read(apiClientProvider).post(
            ApiEndpoints.profileResubmissionSubmit,
            data: form,
            timeout: const Duration(seconds: 90),
          );
      if (res['status'] != true) {
        setState(() => _submitError = res['message']?.toString() ?? 'Could not submit. Please try again.');
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? 'Submitted for verification.')),
      );
      final userJson = res['user'];
      if (userJson is Map) {
        ref.read(authControllerProvider.notifier).updateUser(AppUser.fromJson(userJson.cast<String, dynamic>()));
      } else {
        await _refreshUser();
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _submitError = e.message);
    } catch (_) {
      if (mounted) setState(() => _submitError = 'Could not submit. Please check your connection and try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _logout() async {
    final confirmed = await showLogoutConfirmDialog(context);
    if (confirmed) ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context) {
    final canResubmit = _data?['can_resubmit'] == true;

    return Scaffold(
      appBar: AppBar(
        title: Text(canResubmit || _data == null ? 'Update your documents' : 'Application not approved'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.logout), tooltip: 'Log out', onPressed: _logout),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
              ? _ErrorView(message: _loadError!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _SummaryCard(data: _data!, canResubmit: canResubmit),
                      const SizedBox(height: 16),
                      if (canResubmit) ...[
                        Text('Upload new photos', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(
                          'Take each photo in good light, flat on a table, with the whole document visible and no glare.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        const SizedBox(height: 12),
                        for (final d in _documents)
                          _DocumentCard(
                            label: d['label'].toString(),
                            currentUrl: d['current_url']?.toString(),
                            newPhoto: _newPhotos[d['key']],
                            onPick: _submitting ? null : () => _pickPhoto(d['key'].toString()),
                          ),
                        if (_expiryFields.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          for (final f in _expiryFields) _expiryTile(f),
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'Documents must be valid for at least $_minDays more days. If yours expires sooner, please renew it first.',
                              style: TextStyle(color: Colors.grey[700], fontSize: 12),
                            ),
                          ),
                        ],
                        if (_submitError != null) ...[
                          const SizedBox(height: 12),
                          Text(_submitError!, style: const TextStyle(color: AppColors.red)),
                        ],
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _submitting ? null : _submit,
                          icon: _submitting
                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.send),
                          label: Text(_submitting ? 'Submitting…' : 'Submit for verification'),
                          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                        ),
                      ] else ...[
                        Text(
                          'If you think this is a mistake, please contact our support team.',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Center(
                        child: TextButton.icon(
                          icon: const Icon(Icons.support_agent_outlined),
                          label: const Text('Contact support ($_supportHotlineLabel)'),
                          onPressed: () => launchUrl(Uri(scheme: 'tel', path: _supportHotline)),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          style: TextButton.styleFrom(foregroundColor: Colors.grey[700]),
                          onPressed: () => Navigator.of(context)
                              .push(MaterialPageRoute(builder: (_) => const DeleteAccountScreen())),
                          child: const Text('Delete account'),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _expiryTile(Map<String, dynamic> f) {
    final key = f['key'].toString();
    final date = _expiry[key];
    final tooSoon = date != null && date.isBefore(_minExpiry);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: const Icon(Icons.event_outlined),
        title: Text(f['label'].toString() + (f['required'] == true ? '' : ' (if shown)')),
        subtitle: Text(
          date == null
              ? 'Tap to select'
              : DateFormat('d MMM yyyy').format(date) + (tooSoon ? ' — expires too soon' : ''),
          style: TextStyle(color: tooSoon ? AppColors.red : null),
        ),
        trailing: const Icon(Icons.edit_calendar_outlined),
        onTap: _submitting ? null : () => _pickDate(key),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.data, required this.canResubmit});
  final Map<String, dynamic> data;
  final bool canResubmit;

  @override
  Widget build(BuildContext context) {
    final issues = ((data['issues'] as List?) ?? []).map((e) => e.toString()).toList();
    final note = data['note']?.toString();
    final docs = ((data['documents'] as List?) ?? []).map((d) => (d as Map)['label'].toString()).toList();
    final color = canResubmit ? const Color(0xFFFFF4E5) : const Color(0xFFFDECEC);
    final accent = canResubmit ? const Color(0xFFB26A00) : AppColors.red;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12), border: Border.all(color: accent.withValues(alpha: 0.3))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(canResubmit ? Icons.assignment_late_outlined : Icons.cancel_outlined, color: accent),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  canResubmit ? 'Action needed to complete your registration' : 'Your registration was not approved',
                  style: TextStyle(fontWeight: FontWeight.bold, color: accent),
                ),
              ),
            ],
          ),
          if (issues.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('What we found:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final i in issues) Text('• $i'),
          ],
          if (canResubmit && docs.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Please upload again:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            for (final d in docs) Text('• $d'),
          ],
          if (note != null && note.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Message from our team:', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(note),
          ],
        ],
      ),
    );
  }
}

class _DocumentCard extends StatelessWidget {
  const _DocumentCard({required this.label, required this.currentUrl, required this.newPhoto, required this.onPick});
  final String label;
  final String? currentUrl;
  final File? newPhoto;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    Widget thumb(Widget child, String caption, {Color? border}) => Expanded(
          child: Column(
            children: [
              AspectRatio(
                aspectRatio: 1.5,
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: border ?? Colors.grey.shade300, width: border != null ? 2 : 1),
                  ),
                  child: child,
                ),
              ),
              const SizedBox(height: 4),
              Text(caption, style: TextStyle(fontSize: 12, color: Colors.grey[700])),
            ],
          ),
        );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(newPhoto != null ? Icons.check_circle : Icons.radio_button_unchecked,
                    color: newPhoto != null ? Colors.green : Colors.grey),
                const SizedBox(width: 8),
                Expanded(child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                thumb(
                  currentUrl != null
                      ? Image.network(currentUrl!, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image_outlined)))
                      : const Center(child: Text('None')),
                  'Previous',
                ),
                const SizedBox(width: 10),
                thumb(
                  newPhoto != null
                      ? Image.file(newPhoto!, fit: BoxFit.cover)
                      : const Center(child: Icon(Icons.add_a_photo_outlined, size: 32)),
                  'New',
                  border: newPhoto != null ? Colors.green : null,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.photo_camera_outlined),
                label: Text(newPhoto == null ? 'Take / choose photo' : 'Retake photo'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
