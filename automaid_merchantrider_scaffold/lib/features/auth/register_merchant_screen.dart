import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/widgets/form_section_card.dart';
import 'widgets/map_picker_screen.dart';

/// Full merchant registration — matches MerchantController::register's
/// field list exactly (see AuthRepository.registerMerchant). [typeMerchant]
/// comes from RegisterRoleScreen ('outlet_partner' or 'automaid_outlet').
class RegisterMerchantScreen extends ConsumerStatefulWidget {
  const RegisterMerchantScreen({super.key, required this.typeMerchant});
  final String typeMerchant;

  @override
  ConsumerState<RegisterMerchantScreen> createState() => _RegisterMerchantScreenState();
}

class _RegisterMerchantScreenState extends ConsumerState<RegisterMerchantScreen> {
  int _step = 0;
  bool _isSubmitting = false;
  String? _error;
  int? _userId;

  final _formKey = GlobalKey<FormState>();
  // Same reasoning as the rider registration screen's equivalent field
  // — scrolls back to the top after a failed validation so errors in
  // earlier sections aren't hidden by whatever scroll position the
  // person was at when they tapped Next.
  final _formScrollController = ScrollController();

  // Personal info
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _mobile = TextEditingController();
  String? _idType;
  final _icno = TextEditingController();

  // Address
  final _addressLine1 = TextEditingController();
  final _addressLine2 = TextEditingController();
  final _postcode = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController(text: 'Malaysia');
  String? _selectedState;
  LatLng? _pinnedLocation;

  // Laundry equipment
  final _washerQuantity = TextEditingController();
  final _dryerQuantity = TextEditingController();
  static const _serviceCategoryOptions = ['Dry Cleaning', 'Shoe Cleaning', 'Helmet Cleaning', 'Wash & Dry'];
  final Set<String> _serviceCategories = {};

  // Company information
  final _companyName = TextEditingController();
  final _ssmNo = TextEditingController();
  String? _businessOption;
  // Confirmed from the actual backend column (business_option:
  // 1=Corporate, 2=JV, 3=Franchise) — the earlier guess of
  // 'Sole Proprietor'/'Partnership' was wrong (the flow doc only ever
  // showed one option selected, so the full set had to be inferred,
  // and that inference turned out incorrect — it crashed at
  // registration since the backend didn't recognize those labels).
  static const _businessOptions = ['Corporate', 'JV', 'Franchise'];

  // Bank (optional)
  String? _bankName;
  final _bankNo = TextEditingController();

  // Password
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  // Documents — front-only IC (both merchant types), Business License
  // required. Mirrors the rider registration screen's guided
  // per-document flow.
  File? _icFront, _businessLicense;
  int _docSubStep = 0; // 0=IC, 1=Business License, 2=Declarations, 3=Consents

  // AutoMaid Outlet only — Outlet Partner is MyKad-only, same as rider.
  // AutoMaid Outlet (laundry assistant) is open to foreigners too, so
  // offers a choice of which identity document is being provided.
  String _icDocType = 'MyKad'; // 'MyKad' | 'Passport' | 'Selfie'

  // Declarations (Pengisytiharan) — 3 for merchant (the rider-only
  // vehicle/traffic-law and criminal-conviction declarations are
  // dropped, per explicit instruction).
  bool _decl1 = false, _decl2 = false, _decl3 = false;
  bool get _allDeclarationsAccepted => _decl1 && _decl2 && _decl3;

  // Consents (Persetujuan) — same shape as rider's 4, with the
  // delivery-specific Terms of Service and Code of Conduct swapped for
  // merchant/laundry-assistant equivalents.
  bool _consent1 = false, _consent2 = false, _consent3 = false, _consent4 = false;
  bool get _allConsentsAccepted => _consent1 && _consent2 && _consent3 && _consent4;

  late final _privacyNoticeRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/privacy_notice.html');
  late final _merchantTermsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/terms_of_svc_merchant.html');
  late final _paymentTermsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/terms_of_service_payments.html');
  late final _merchantCodeOfConductRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/merchant_code_of_conduct.html');

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  // OTP
  final _otp = TextEditingController();

  static const _idTypes = ['NRIC', 'Passport'];

  @override
  void dispose() {
    for (final c in [
      _name, _email, _mobile, _icno, _addressLine1, _addressLine2, _postcode, _city, _country,
      _washerQuantity, _dryerQuantity, _companyName, _ssmNo, _bankNo, _password, _confirmPassword, _otp,
    ]) {
      c.dispose();
    }
    _formScrollController.dispose();
    _privacyNoticeRecognizer.dispose();
    _merchantTermsRecognizer.dispose();
    _paymentTermsRecognizer.dispose();
    _merchantCodeOfConductRecognizer.dispose();
    super.dispose();
  }

  String get _normalizedMobile {
    var digits = _mobile.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '60$digits';
  }

  Future<void> _pickLocation() async {
    final result = await Navigator.of(context)
        .push<LatLng>(MaterialPageRoute(builder: (_) => MapPickerScreen(initialPosition: _pinnedLocation)));
    if (result != null) setState(() => _pinnedLocation = result);
  }

  Future<void> _pickDocument(void Function(File) onPicked) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.camera, imageQuality: 85);
    if (picked != null) setState(() => onPicked(File(picked.path)));
  }

  bool get _requiredDocumentsAttached => _icFront != null && _businessLicense != null;

  /// Explicit, direct check of every required field's actual value —
  /// same approach as the rider registration screen, for the same
  /// reason: don't rely solely on TextFormField's own inline red-text
  /// rendering to make a validation failure visible.
  List<String> _collectMissingFields() {
    final missing = <String>[];

    if (_name.text.trim().isEmpty) missing.add('Full Name');
    if (!_email.text.contains('@')) missing.add('Email');
    if (_mobile.text.replaceAll(RegExp(r'\D'), '').length < 9) missing.add('Mobile phone');
    if (_idType == null) missing.add('ID Type');
    if (_icno.text.trim().isEmpty) missing.add('${_idType ?? "ID"} Number');

    if (_addressLine1.text.trim().isEmpty) missing.add('Address line 1');
    if (_postcode.text.trim().isEmpty) missing.add('Postcode');
    if (_city.text.trim().isEmpty) missing.add('City');
    if (_selectedState == null) missing.add('State');
    if (_country.text.trim().isEmpty) missing.add('Country');
    if (_pinnedLocation == null) missing.add('Pinned outlet location on map');

    if (_washerQuantity.text.trim().isEmpty) missing.add('Washer quantity');
    if (_dryerQuantity.text.trim().isEmpty) missing.add('Dryer quantity');
    if (_serviceCategories.isEmpty) missing.add('Service categories (at least one)');

    if (_companyName.text.trim().isEmpty) missing.add('Business name');
    if (_ssmNo.text.trim().isEmpty) missing.add('Business License');
    if (_businessOption == null) missing.add('Business options');

    if (_password.text.length < 8) missing.add('Password (at least 8 characters)');
    if (_confirmPassword.text != _password.text || _confirmPassword.text.isEmpty) {
      missing.add('Confirm password (must match Password)');
    }

    return missing;
  }

  Future<void> _showMissingFieldsDialog(List<String> missing) {
    return showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Please complete these fields'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: missing.map((f) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text('•  $f'),
            )).toList(),
          ),
        ),
        actions: [
          FilledButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _submitForm() async {
    // Still run Form's own validate() too — a second, complementary
    // layer on top of the explicit dialog below, not a replacement.
    _formKey.currentState?.validate();

    final missing = _collectMissingFields();
    if (missing.isNotEmpty) {
      _formScrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      await _showMissingFieldsDialog(missing);
      return;
    }
    setState(() {
      _error = null;
      _step = 1;
    });
  }

  Future<void> _submitRegistration() async {
    if (!_requiredDocumentsAttached) {
      setState(() => _error = 'Please attach all required documents before continuing.');
      return;
    }
    if (!_allDeclarationsAccepted) {
      setState(() => _error = 'Please accept all declarations before continuing.');
      return;
    }
    if (!_allConsentsAccepted) {
      setState(() => _error = 'Please accept all consents before continuing.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final result = await ref.read(authRepositoryProvider).registerMerchant(
            name: _name.text.trim(),
            email: _email.text.trim(),
            mobileNo: _normalizedMobile,
            password: _password.text,
            passwordConfirmation: _confirmPassword.text,
            icno: _icno.text.trim(),
            idType: _idType ?? '',
            addressLine1: _addressLine1.text.trim(),
            addressLine2: _addressLine2.text.trim(),
            countryName: _country.text.trim(),
            stateName: _selectedState ?? '',
            postcode: _postcode.text.trim(),
            city: _city.text.trim(),
            typeMerchant: widget.typeMerchant,
            washerQuantity: int.tryParse(_washerQuantity.text.trim()) ?? 0,
            dryerQuantity: int.tryParse(_dryerQuantity.text.trim()) ?? 0,
            serviceCategories: _serviceCategories.toList(),
            companyName: _companyName.text.trim(),
            ssmNo: _ssmNo.text.trim(),
            businessOption: _businessOption ?? '',
            bankName: _bankName,
            bankNo: _bankNo.text.trim().isEmpty ? null : _bankNo.text.trim(),
            latitude: _pinnedLocation!.latitude,
            longitude: _pinnedLocation!.longitude,
            icFrontPath: _icFront!.path,
            ssmCertPath: _businessLicense!.path,
          );
      if (result.status && result.userId != null) {
        setState(() {
          _userId = result.userId;
          _step = 2;
        });
      } else {
        setState(() => _error = result.message);
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _submitOtp() async {
    if (_otp.text.trim().isEmpty || _userId == null) {
      setState(() => _error = 'Please enter the OTP sent to your phone.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final result = await ref
          .read(authControllerProvider.notifier)
          .verifyRegisterMerchant(userId: _userId!, otp: _otp.text.trim());
      if (!result.status) {
        setState(() => _error = result.message ?? 'Invalid OTP.');
        return;
      }
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _resendOtp() async {
    final result = await ref.read(authControllerProvider.notifier).resendOtp(_email.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Step ${_step + 1}/3')),
      body: Column(
        children: [
          StepProgressBar(currentStep: _step, totalSteps: 3),
          Expanded(
            child: IndexedStack(
              index: _step,
              children: [
                _buildFormStep(),
                _buildDocumentsStep(),
                _buildOtpStep(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFormStep() {
    return Form(
      key: _formKey,
      child: ListView(
        controller: _formScrollController,
        padding: const EdgeInsets.all(16),
        children: [
          Text('New Merchant registration', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Tell us about your outlet.', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
            'Registering as ${widget.typeMerchant == 'automaid_outlet' ? 'Auto Maid Outlet' : 'Outlet Partner'}. '
            'All fields with * are required.',
            style: TextStyle(color: Colors.grey[600], fontSize: 12.5, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),
          FormSectionCard(
            icon: Icons.person_outline,
            title: 'Personal Information',
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Full Name *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Email *'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Enter a valid email' : null,
              ),
              TextFormField(
                controller: _mobile,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Mobile phone *', prefixText: '+60 '),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return digits.length < 9 ? 'Enter a valid mobile number' : null;
                },
              ),
              DropdownButtonFormField<String>(
                value: _idType,
                decoration: const InputDecoration(labelText: 'ID Type *'),
                items: _idTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _idType = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              TextFormField(
                controller: _icno,
                decoration: InputDecoration(labelText: '${_idType ?? "ID"} Number *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ],
          ),
          FormSectionCard(
            icon: Icons.storefront_outlined,
            title: 'Outlet Address',
            children: [
              TextFormField(
                controller: _addressLine1,
                decoration: const InputDecoration(labelText: 'Address line 1 *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _addressLine2,
                decoration: const InputDecoration(labelText: 'Address line 2'),
              ),
              TextFormField(
                controller: _postcode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Postcode *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _city,
                decoration: const InputDecoration(labelText: 'City *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              Consumer(
                builder: (context, ref, _) {
                  final statesAsync = ref.watch(statesProvider);
                  return statesAsync.when(
                    data: (states) => DropdownButtonFormField<String>(
                      value: _selectedState,
                      decoration: const InputDecoration(labelText: 'State *'),
                      items: states.map((s) => DropdownMenuItem(value: s.name, child: Text(s.name))).toList(),
                      onChanged: (v) => setState(() => _selectedState = v),
                      validator: (v) => v == null ? 'Required' : null,
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                    error: (e, _) => Text('Could not load states: $e'),
                  );
                },
              ),
              TextFormField(
                controller: _country,
                decoration: const InputDecoration(labelText: 'Country *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              OutlinedButton.icon(
                onPressed: _pickLocation,
                icon: Icon(_pinnedLocation == null ? Icons.map_outlined : Icons.check_circle, size: 18),
                label: Text(_pinnedLocation == null ? 'Pin outlet location on map' : 'Location pinned — tap to adjust'),
              ),
            ],
          ),
          FormSectionCard(
            icon: Icons.local_laundry_service_outlined,
            title: 'Laundry Equipment Details',
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _washerQuantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Washer quantity *'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _dryerQuantity,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Dryer quantity *'),
                      validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Service categories *'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: _serviceCategoryOptions.map((c) {
                      final selected = _serviceCategories.contains(c);
                      return FilterChip(
                        label: Text(c),
                        selected: selected,
                        onSelected: (v) => setState(() {
                          if (v) {
                            _serviceCategories.add(c);
                          } else {
                            _serviceCategories.remove(c);
                          }
                        }),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ],
          ),
          FormSectionCard(
            icon: Icons.business_outlined,
            title: 'Business Information',
            children: [
              TextFormField(
                controller: _companyName,
                decoration: const InputDecoration(labelText: 'Business name *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _ssmNo,
                decoration: const InputDecoration(labelText: 'Business License *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                value: _businessOption,
                decoration: const InputDecoration(labelText: 'Business options *'),
                items: _businessOptions.map((o) => DropdownMenuItem(value: o, child: Text(o))).toList(),
                onChanged: (v) => setState(() => _businessOption = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
            ],
          ),
          FormSectionCard(
            icon: Icons.account_balance_outlined,
            title: 'Bank Information (optional)',
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final banksAsync = ref.watch(banksProvider);
                  return banksAsync.when(
                    data: (banks) => DropdownButtonFormField<String>(
                      value: _bankName,
                      decoration: const InputDecoration(labelText: 'Bank name'),
                      items: banks.map((b) => DropdownMenuItem(value: b.name, child: Text(b.name))).toList(),
                      onChanged: (v) => setState(() => _bankName = v),
                    ),
                    loading: () => const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    ),
                    error: (e, _) => Text('Could not load banks: $e'),
                  );
                },
              ),
              TextFormField(
                controller: _bankNo,
                decoration: const InputDecoration(labelText: 'Bank account number'),
              ),
            ],
          ),
          FormSectionCard(
            icon: Icons.lock_outline,
            title: 'Create Password',
            children: [
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Password *'),
                validator: (v) => (v == null || v.length < 8) ? 'At least 8 characters' : null,
              ),
              TextFormField(
                controller: _confirmPassword,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirm password *'),
                validator: (v) => v != _password.text ? 'Passwords do not match' : null,
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 4),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 8),
          FilledButton(onPressed: _submitForm, child: const Text('Next')),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildDocumentsStep() {
    // A mini 4-screen wizard inside Step 2 — Identity Card -> Business
    // License -> Declarations -> Consents. Mirrors the rider
    // registration screen's structure; content differs per merchant
    // type (Outlet Partner vs AutoMaid Outlet) for the Identity Card
    // screen specifically, and the Declarations/Consents content is
    // merchant-specific throughout.
    switch (_docSubStep) {
      case 0:
        return _buildIdentityCardStep();
      case 1:
        return _DocumentGuidelineStep(
          title: 'Business License Upload Guidelines',
          sampleImageAsset: 'assets/images/business_license_sample.jpg',
          requirements: const [
            'Full-color business license showing all 4 edges of the card '
                'with the detail (front of the Business License).',
            'Must be valid (not expired).',
            'All text is readable and not blurred.',
          ],
          thingsToAvoid: const [
            'Blurry image.',
            'Black & white image.',
          ],
          uploadedFile: _businessLicense,
          onUpload: () => _pickDocument((f) => _businessLicense = f),
          onNext: _businessLicense == null ? null : () => setState(() => _docSubStep = 2),
          onBack: () => setState(() => _docSubStep = 0),
        );
      case 2:
        return _MerchantDeclarationsStep(
          decl1: _decl1,
          decl2: _decl2,
          decl3: _decl3,
          onChanged1: (v) => setState(() => _decl1 = v),
          onChanged2: (v) => setState(() => _decl2 = v),
          onChanged3: (v) => setState(() => _decl3 = v),
          onNext: _allDeclarationsAccepted ? () => setState(() => _docSubStep = 3) : null,
          onBack: () => setState(() => _docSubStep = 1),
        );
      case 3:
      default:
        return _MerchantConsentsStep(
          consent1: _consent1,
          consent2: _consent2,
          consent3: _consent3,
          consent4: _consent4,
          onChanged1: (v) => setState(() => _consent1 = v),
          onChanged2: (v) => setState(() => _consent2 = v),
          onChanged3: (v) => setState(() => _consent3 = v),
          onChanged4: (v) => setState(() => _consent4 = v),
          privacyNoticeRecognizer: _privacyNoticeRecognizer,
          merchantTermsRecognizer: _merchantTermsRecognizer,
          paymentTermsRecognizer: _paymentTermsRecognizer,
          merchantCodeOfConductRecognizer: _merchantCodeOfConductRecognizer,
          onNext: (_allConsentsAccepted && !_isSubmitting) ? _submitRegistration : null,
          isSubmitting: _isSubmitting,
          onBack: () => setState(() => _docSubStep = 2),
          error: _error,
        );
    }
  }

  /// Identity Card guidelines differ by merchant type: Outlet Partner
  /// is MyKad-only, identical to the rider screen's IC requirements.
  /// AutoMaid Outlet (laundry assistant) is open to foreigners, so
  /// drops the MyKad-specific requirement/avoid item and offers a
  /// choice of document type instead.
  Widget _buildIdentityCardStep() {
    final isAutoMaidOutlet = widget.typeMerchant == 'automaid_outlet';

    return _DocumentGuidelineStep(
      title: 'Identity Card Upload Guidelines',
      sampleImageAsset: 'assets/images/identity_card_sample.jpg',
      requirements: isAutoMaidOutlet
          ? const [
              'Age 18 – 69 years old.',
              'All text is readable and unobstructed.',
            ]
          : const [
              'Age 18 – 69 years old.',
              'Blue Malaysian MyKad, full-color, showing all 4 edges of the '
                  'card and personal information (front of the MyKad).',
              'All text is readable and unobstructed.',
            ],
      thingsToAvoid: isAutoMaidOutlet
          ? const ['Black & white image.']
          : const [
              'Not a Malaysian Blue MyKad.',
              'Black & white image.',
            ],
      extraContent: isAutoMaidOutlet
          ? [
              const SizedBox(height: 16),
              const Text('Document type', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'MyKad', label: Text('MyKad')),
                  ButtonSegment(value: 'Passport', label: Text('Passport')),
                  ButtonSegment(value: 'Selfie', label: Text('Selfie')),
                ],
                selected: {_icDocType},
                onSelectionChanged: (v) => setState(() => _icDocType = v.first),
              ),
            ]
          : null,
      uploadedFile: _icFront,
      onUpload: () => _pickDocument((f) => _icFront = f),
      onNext: _icFront == null ? null : () => setState(() => _docSubStep = 1),
      onBack: () => setState(() => _step = 0),
    );
  }

  Widget _buildOtpStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('We sent a code to +60 ${_mobile.text.trim()}.'),
        const SizedBox(height: 12),
        TextField(
          controller: _otp,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'OTP code'),
        ),
        TextButton(onPressed: _resendOtp, child: const Text('Resend OTP')),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _isSubmitting ? null : _submitOtp,
          child: _isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Verify & finish'),
        ),
      ],
    );
  }
}

/// One guided document-upload screen — sample photo, requirements,
/// things to avoid, an optional extra content block (used for the
/// Identity Card document-type selector), an Upload button, and Next
/// (disabled until uploaded). Local to this file rather than shared
/// with the rider registration screen's equivalent, to avoid touching
/// that already-working screen for this change.
class _DocumentGuidelineStep extends StatelessWidget {
  const _DocumentGuidelineStep({
    required this.title,
    required this.sampleImageAsset,
    required this.requirements,
    required this.thingsToAvoid,
    required this.uploadedFile,
    required this.onUpload,
    required this.onNext,
    required this.onBack,
    this.extraContent,
    this.nextLabel = 'Next',
    this.isSubmitting = false,
    this.error,
  });

  final String title;
  final String sampleImageAsset;
  final List<String> requirements;
  final List<String> thingsToAvoid;
  final File? uploadedFile;
  final VoidCallback onUpload;
  final VoidCallback? onNext;
  final VoidCallback onBack;
  final List<Widget>? extraContent;
  final String nextLabel;
  final bool isSubmitting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        Text('Sample photo', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.grey[800])),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(sampleImageAsset, width: double.infinity, fit: BoxFit.contain),
        ),
        const SizedBox(height: 20),
        const Text('Requirements:', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        for (int i = 0; i < requirements.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text('${i + 1}. ${requirements[i]}', style: const TextStyle(fontSize: 13.5)),
          ),
        const SizedBox(height: 14),
        Text('Things to avoid:', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.red[700])),
        const SizedBox(height: 6),
        for (int i = 0; i < thingsToAvoid.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${i + 1}. ${thingsToAvoid[i]}',
              style: TextStyle(fontSize: 13.5, color: Colors.red[700]),
            ),
          ),
        if (extraContent != null) ...extraContent!,
        const SizedBox(height: 22),
        OutlinedButton.icon(
          onPressed: onUpload,
          icon: Icon(
            uploadedFile != null ? Icons.check_circle : Icons.upload_file_outlined,
            color: uploadedFile != null ? Colors.green : null,
          ),
          label: Text(uploadedFile != null ? 'Document uploaded — tap to retake' : 'Upload Document'),
        ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 22),
        FilledButton(
          onPressed: onNext,
          child: isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(nextLabel),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onBack, child: const Text('Back')),
      ],
    );
  }
}

/// Declarations (Pengisytiharan) — 3 checkboxes for merchant (the
/// rider-only vehicle/traffic-law and criminal-conviction items
/// dropped, per explicit instruction).
class _MerchantDeclarationsStep extends StatelessWidget {
  const _MerchantDeclarationsStep({
    required this.decl1,
    required this.decl2,
    required this.decl3,
    required this.onChanged1,
    required this.onChanged2,
    required this.onChanged3,
    required this.onNext,
    required this.onBack,
  });

  final bool decl1, decl2, decl3;
  final ValueChanged<bool> onChanged1, onChanged2, onChanged3;
  final VoidCallback? onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        decl1,
        onChanged1,
        'Saya tidak mempunyai sebarang keadaan kesihatan yang mungkin '
            'menyebabkan saya tidak dapat menjalankan tugas dengan selamat.'
      ),
      (
        decl2,
        onChanged2,
        'Saya membenarkan LB Pickup and Delivery dan ejen atau wakilnya untuk '
            'menjalankan semakan latar belakang terhadap saya untuk tujuan '
            'permohonan sebagai rakan kedai/pembantu dobi.'
      ),
      (
        decl3,
        onChanged3,
        'Saya dengan ini mengisytiharkan bahawa semua maklumat, butiran '
            'pengenalan diri, dan dokumen perniagaan yang dikemukakan dalam '
            'permohonan ini adalah benar, tepat, dan terkini.'
      ),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Declarations (Pengisytiharan)',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CheckboxListTile(
              value: item.$1,
              onChanged: (v) => item.$2(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(item.$3, style: const TextStyle(fontSize: 13.5)),
            ),
          ),
        const SizedBox(height: 18),
        FilledButton(
          onPressed: onNext,
          child: const Text('Next'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onBack, child: const Text('Back')),
      ],
    );
  }
}

/// Consents (Persetujuan) — same shape as rider's, with the
/// delivery-specific Terms of Service and Code of Conduct replaced by
/// merchant/laundry-assistant equivalents.
class _MerchantConsentsStep extends StatelessWidget {
  const _MerchantConsentsStep({
    required this.consent1,
    required this.consent2,
    required this.consent3,
    required this.consent4,
    required this.onChanged1,
    required this.onChanged2,
    required this.onChanged3,
    required this.onChanged4,
    required this.privacyNoticeRecognizer,
    required this.merchantTermsRecognizer,
    required this.paymentTermsRecognizer,
    required this.merchantCodeOfConductRecognizer,
    required this.onNext,
    required this.onBack,
    this.isSubmitting = false,
    this.error,
  });

  final bool consent1, consent2, consent3, consent4;
  final ValueChanged<bool> onChanged1, onChanged2, onChanged3, onChanged4;
  final TapGestureRecognizer privacyNoticeRecognizer;
  final TapGestureRecognizer merchantTermsRecognizer;
  final TapGestureRecognizer paymentTermsRecognizer;
  final TapGestureRecognizer merchantCodeOfConductRecognizer;
  final VoidCallback? onNext;
  final VoidCallback onBack;
  final bool isSubmitting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (consent1, onChanged1, 'Notis Privasi', privacyNoticeRecognizer),
      (consent2, onChanged2, 'Terms of Service - Merchant outlet and Laundry Assistant', merchantTermsRecognizer),
      (consent3, onChanged3, 'Terms of Service - Payment and Rewards', paymentTermsRecognizer),
      (consent4, onChanged4, 'Code of Conduct - Merchant Outlet and Laundry Assistant', merchantCodeOfConductRecognizer),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Consents (Persetujuan)',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        const Text(
          'Saya mengakui bahawa dengan mengemukakan permohonan saya, saya '
          'telah membaca, memahami dan bersetuju dengan:',
          style: TextStyle(fontSize: 13.5),
        ),
        const SizedBox(height: 12),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: CheckboxListTile(
              value: item.$1,
              onChanged: (v) => item.$2(v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: RichText(
                text: TextSpan(
                  style: TextStyle(fontSize: 13.5, color: scheme.onSurface),
                  children: [
                    TextSpan(
                      text: item.$3,
                      style: TextStyle(color: scheme.primary, decoration: TextDecoration.underline),
                      recognizer: item.$4,
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (error != null) ...[
          const SizedBox(height: 12),
          Text(error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 18),
        FilledButton(
          onPressed: onNext,
          child: isSubmitting
              ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Continue'),
        ),
        const SizedBox(height: 8),
        TextButton(onPressed: onBack, child: const Text('Back')),
      ],
    );
  }
}
