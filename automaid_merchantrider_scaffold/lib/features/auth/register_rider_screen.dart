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

/// Full rider registration — matches RiderController::register's field
/// list exactly (see AuthRepository.registerRider). [typeRider] comes
/// from RegisterRoleScreen ('gig' or 'staff').
///
/// All 5 verification documents (IC front/back, license front/back, AND
/// JPJ grant) are required here — the flow spec explicitly flagged that
/// the previous app never collected the JPJ grant even though the
/// backend has always supported it (RiderController::register accepts
/// `jpj_grant` alongside the other 4 files). Continue only enables once
/// all 5 are attached.
class RegisterRiderScreen extends ConsumerStatefulWidget {
  const RegisterRiderScreen({super.key, required this.typeRider});
  final String typeRider;

  @override
  ConsumerState<RegisterRiderScreen> createState() => _RegisterRiderScreenState();
}

class _RegisterRiderScreenState extends ConsumerState<RegisterRiderScreen> {
  int _step = 0;
  bool _isSubmitting = false;
  String? _error;
  int? _userId;

  final _formKey = GlobalKey<FormState>();
  // No auto-scroll-to-error by default in Flutter — without this, a
  // validation failure on an early section (Personal Information,
  // Address, Emergency Contact) sets its red error text correctly, but
  // if the person has already scrolled down to fill in Vehicle/Bank/
  // Password near the bottom, that error is invisible off-screen. Easy
  // to mistake for "validation isn't happening on those fields" when
  // it actually did — it's just not visible from the current scroll
  // position.
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

  // Emergency contact
  final _emergencyName = TextEditingController();
  final _emergencyPhone = TextEditingController();
  final _emergencyRelation = TextEditingController();

  // Vehicle
  String? _vehicleType;
  final _plateNo = TextEditingController();
  final _vehicleMake = TextEditingController();
  final _vehicleModel = TextEditingController();
  String? _vehicleColor;
  final _vehicleColorOther = TextEditingController();

  // Bank (optional)
  String? _bankName;
  final _bankNo = TextEditingController();

  // Password
  final _password = TextEditingController();
  final _confirmPassword = TextEditingController();

  // Documents — front-only now, per the guided per-document upload
  // flow. Back-side fields still exist on the backend (optionally) but
  // are no longer collected here.
  File? _icFront, _licenseFront, _jpjGrant;
  int _docSubStep = 0; // 0=IC, 1=License, 2=RoadTax, 3=Declarations, 4=Consents

  // Declarations (Pengisytiharan) — all 5 required before Consents.
  bool _decl1 = false, _decl2 = false, _decl3 = false, _decl4 = false, _decl5 = false;
  bool get _allDeclarationsAccepted => _decl1 && _decl2 && _decl3 && _decl4 && _decl5;

  // Consents (Persetujuan) — all 4 required before OTP is sent.
  bool _consent1 = false, _consent2 = false, _consent3 = false, _consent4 = false;
  bool get _allConsentsAccepted => _consent1 && _consent2 && _consent3 && _consent4;

  late final _privacyNoticeRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/privacy_notice.html');
  late final _deliveryTermsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/terms_of_svc_delivery.html');
  late final _paymentTermsRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/terms_of_service_payments.html');
  late final _codeOfConductRecognizer = TapGestureRecognizer()
    ..onTap = () => _openLink('https://lbunlimitedwash.com/policy/driver_code_of_conduct.html');

  Future<void> _openLink(String url) async {
    final uri = Uri.parse(url);
    await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
  }

  // OTP
  final _otp = TextEditingController();

  static const _idTypes = ['NRIC', 'Passport'];
  static const _vehicleTypes = ['Motorcycle', 'Car', 'Van', 'Bicycle'];
  static const _vehicleColors = ['Black', 'White', 'Red', 'Blue', 'Silver', 'Other'];

  @override
  void dispose() {
    for (final c in [
      _name, _email, _mobile, _icno, _addressLine1, _addressLine2, _postcode, _city, _country,
      _emergencyName, _emergencyPhone, _emergencyRelation, _plateNo, _vehicleMake, _vehicleModel,
      _vehicleColorOther, _bankNo, _password, _confirmPassword, _otp,
    ]) {
      c.dispose();
    }
    _privacyNoticeRecognizer.dispose();
    _deliveryTermsRecognizer.dispose();
    _paymentTermsRecognizer.dispose();
    _codeOfConductRecognizer.dispose();
    _formScrollController.dispose();
    super.dispose();
  }

  String get _normalizedMobile {
    var digits = _mobile.text.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) digits = digits.substring(1);
    return '60$digits';
  }

  String get _normalizedEmergencyPhone {
    var digits = _emergencyPhone.text.replaceAll(RegExp(r'\D'), '');
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

  bool get _allDocumentsAttached => _icFront != null && _licenseFront != null && _jpjGrant != null;

  /// Explicit, direct check of every required field's actual value —
  /// deliberately NOT relying on TextFormField's own inline red-text
  /// rendering, which wasn't reliably showing for some sections even
  /// after confirming the validators themselves were correct and
  /// scrolling to the top. This computes the same rules independently
  /// and returns a plain list of what's missing, so _submitForm can
  /// show it in a dialog no rendering quirk can hide.
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
    if (_pinnedLocation == null) missing.add('Pinned map location');

    if (_emergencyName.text.trim().isEmpty) missing.add('Emergency contact name');
    if (_emergencyPhone.text.replaceAll(RegExp(r'\D'), '').length < 9) {
      missing.add('Emergency contact phone');
    }
    if (_emergencyRelation.text.trim().isEmpty) missing.add('Emergency contact relation');

    if (_vehicleType == null) missing.add('Vehicle type');
    if (_plateNo.text.trim().isEmpty) missing.add('Plate number');
    if (_vehicleMake.text.trim().isEmpty) missing.add('Vehicle make');
    if (_vehicleModel.text.trim().isEmpty) missing.add('Vehicle model');
    if (_vehicleColor == 'Other' && _vehicleColorOther.text.trim().isEmpty) {
      missing.add('Vehicle colour (other)');
    }

    if (_bankName == null) missing.add('Bank name');
    if (_bankNo.text.trim().isEmpty) missing.add('Bank account number');

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
    // Still run Form's own validate() too — sets inline red text
    // wherever it does render correctly, as a second layer on top of
    // the explicit dialog below, not a replacement for it.
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
    setState(() => _step = 1);
  }

  Future<void> _submitRegistration() async {
    if (!_allDocumentsAttached) {
      setState(() => _error = 'Please attach all 3 documents before continuing.');
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
      final result = await ref.read(authRepositoryProvider).registerRider(
            name: _name.text.trim(),
            email: _email.text.trim(),
            mobileNo: _normalizedMobile,
            password: _password.text,
            passwordConfirmation: _confirmPassword.text,
            icno: _icno.text.trim(),
            idType: _idType,
            addressLine1: _addressLine1.text.trim(),
            addressLine2: _addressLine2.text.trim(),
            countryName: _country.text.trim(),
            stateName: _selectedState ?? '',
            postcode: _postcode.text.trim(),
            city: _city.text.trim(),
            typeRider: widget.typeRider,
            typeVehicle: _vehicleType ?? '',
            emergencyName: _emergencyName.text.trim(),
            emergencyPhone: _normalizedEmergencyPhone,
            emergencyRelation: _emergencyRelation.text.trim(),
            plateNo: _plateNo.text.trim(),
            vehicleMake: _vehicleMake.text.trim(),
            vehicleModel: _vehicleModel.text.trim(),
            vehicleColor: _vehicleColor == 'Other' ? _vehicleColorOther.text.trim() : _vehicleColor,
            bankName: _bankName,
            bankNo: _bankNo.text.trim(),
            latitude: _pinnedLocation!.latitude,
            longitude: _pinnedLocation!.longitude,
            icFrontPath: _icFront!.path,
            licenseFrontPath: _licenseFront!.path,
            jpjGrantPath: _jpjGrant!.path,
            declarationAccepted: _allDeclarationsAccepted,
            consentAccepted: _allConsentsAccepted,
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
          .verifyRegisterRider(userId: _userId!, otp: _otp.text.trim());
      if (!result.status) {
        setState(() => _error = result.message ?? 'Invalid OTP.');
        return;
      }
      // Router redirects automatically once auth state flips — it'll
      // land on the pending-approval screen since status is ONBOARDING
      // until admin approves.
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
          Text('New rider registration', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Tell us about yourself.', style: TextStyle(color: Colors.grey[600])),
          const SizedBox(height: 4),
          Text(
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
            icon: Icons.location_on_outlined,
            title: 'Address',
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
                label: Text(_pinnedLocation == null ? 'Pin address on map' : 'Location pinned — tap to adjust'),
              ),
            ],
          ),
          FormSectionCard(
            icon: Icons.emergency_outlined,
            title: 'Emergency Contact',
            children: [
              TextFormField(
                controller: _emergencyName,
                decoration: const InputDecoration(labelText: 'Full name *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _emergencyPhone,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Phone *', prefixText: '+60 '),
                validator: (v) {
                  final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
                  return digits.length < 9 ? 'Enter a valid phone number' : null;
                },
              ),
              TextFormField(
                controller: _emergencyRelation,
                decoration: const InputDecoration(labelText: 'Relation *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
            ],
          ),
          FormSectionCard(
            icon: Icons.two_wheeler_outlined,
            title: 'Vehicle Information',
            description: 'Choose your service preference.',
            children: [
              DropdownButtonFormField<String>(
                value: _vehicleType,
                decoration: const InputDecoration(labelText: 'Vehicle type *'),
                items: _vehicleTypes.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                onChanged: (v) => setState(() => _vehicleType = v),
                validator: (v) => v == null ? 'Required' : null,
              ),
              TextFormField(
                controller: _plateNo,
                decoration: const InputDecoration(labelText: 'Plate number *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _vehicleMake,
                decoration: const InputDecoration(labelText: 'Vehicle make *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              TextFormField(
                controller: _vehicleModel,
                decoration: const InputDecoration(labelText: 'Vehicle model *'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                value: _vehicleColor,
                decoration: const InputDecoration(labelText: 'Vehicle colour'),
                items: _vehicleColors.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _vehicleColor = v),
              ),
              if (_vehicleColor == 'Other')
                TextFormField(
                  controller: _vehicleColorOther,
                  decoration: const InputDecoration(labelText: 'Colour (other) *'),
                  validator: (v) =>
                      (_vehicleColor == 'Other' && (v == null || v.isEmpty)) ? 'Required' : null,
                ),
            ],
          ),
          FormSectionCard(
            icon: Icons.account_balance_outlined,
            title: 'Bank Information',
            children: [
              Consumer(
                builder: (context, ref, _) {
                  final banksAsync = ref.watch(banksProvider);
                  return banksAsync.when(
                    data: (banks) => DropdownButtonFormField<String>(
                      value: _bankName,
                      decoration: const InputDecoration(labelText: 'Bank name *'),
                      items: banks.map((b) => DropdownMenuItem(value: b.name, child: Text(b.name))).toList(),
                      onChanged: (v) => setState(() => _bankName = v),
                      validator: (v) => v == null ? 'Required' : null,
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
                decoration: const InputDecoration(labelText: 'Bank account number *'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
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
    // A mini 5-screen wizard inside Step 2 — Identity Card -> Driving
    // License -> Road Tax -> Declarations -> Consents. Each document
    // screen only advances once that specific document is attached;
    // Declarations/Consents only advance once every checkbox on that
    // screen is checked. Registration (and the OTP send that triggers)
    // only happens after Consents' "Continue" — i.e. after everything
    // in this whole step is accepted, not partway through.
    switch (_docSubStep) {
      case 0:
        return _DocumentGuidelineStep(
          title: 'Identity Card Upload Guidelines',
          sampleImageAsset: 'assets/images/identity_card_sample.jpg',
          requirements: const [
            'Age 18 – 69 years old.',
            'Blue Malaysian MyKad, full-color, showing all 4 edges of the '
                'card and personal information (front of the MyKad).',
            'All text is readable and unobstructed.',
          ],
          thingsToAvoid: const [
            'Not a Malaysian Blue MyKad.',
            'Black & white image.',
          ],
          uploadedFile: _icFront,
          onUpload: () => _pickDocument((f) => _icFront = f),
          onNext: _icFront == null ? null : () => setState(() => _docSubStep = 1),
          onBack: () => setState(() => _step = 0),
        );
      case 1:
        return _DocumentGuidelineStep(
          title: 'Driving License Upload Guidelines',
          sampleImageAsset: 'assets/images/lesen_memandu_sample.jpg',
          requirements: const [
            'Full-color license showing all 4 edges of the card with '
                'personal detail (front of the Driving License).',
            'Must be valid (not expired).',
            'Must be class B, B1 or B2, D.',
            'All text is readable and not blurred.',
          ],
          thingsToAvoid: const [
            'L License.',
            'Black & white image.',
          ],
          uploadedFile: _licenseFront,
          onUpload: () => _pickDocument((f) => _licenseFront = f),
          onNext: _licenseFront == null ? null : () => setState(() => _docSubStep = 2),
          onBack: () => setState(() => _docSubStep = 0),
        );
      case 2:
        return _DocumentGuidelineStep(
          title: 'Road Tax Upload Guidelines',
          sampleImageAsset: 'assets/images/roadtax_sample.png',
          requirements: const [
            'Full-color road tax showing all 4 edges of the card with the '
                'detail (front of the Road Tax).',
            'Must be valid (not expired).',
            'All text is readable and not blurred.',
          ],
          thingsToAvoid: const [
            'Blurry image.',
            'Black & white image.',
          ],
          uploadedFile: _jpjGrant,
          onUpload: () => _pickDocument((f) => _jpjGrant = f),
          onNext: _jpjGrant == null ? null : () => setState(() => _docSubStep = 3),
          onBack: () => setState(() => _docSubStep = 1),
        );
      case 3:
        return _DeclarationsStep(
          decl1: _decl1,
          decl2: _decl2,
          decl3: _decl3,
          decl4: _decl4,
          decl5: _decl5,
          onChanged1: (v) => setState(() => _decl1 = v),
          onChanged2: (v) => setState(() => _decl2 = v),
          onChanged3: (v) => setState(() => _decl3 = v),
          onChanged4: (v) => setState(() => _decl4 = v),
          onChanged5: (v) => setState(() => _decl5 = v),
          onNext: _allDeclarationsAccepted ? () => setState(() => _docSubStep = 4) : null,
          onBack: () => setState(() => _docSubStep = 2),
        );
      case 4:
      default:
        return _ConsentsStep(
          consent1: _consent1,
          consent2: _consent2,
          consent3: _consent3,
          consent4: _consent4,
          onChanged1: (v) => setState(() => _consent1 = v),
          onChanged2: (v) => setState(() => _consent2 = v),
          onChanged3: (v) => setState(() => _consent3 = v),
          onChanged4: (v) => setState(() => _consent4 = v),
          privacyNoticeRecognizer: _privacyNoticeRecognizer,
          deliveryTermsRecognizer: _deliveryTermsRecognizer,
          paymentTermsRecognizer: _paymentTermsRecognizer,
          codeOfConductRecognizer: _codeOfConductRecognizer,
          onNext: (_allConsentsAccepted && !_isSubmitting) ? _submitRegistration : null,
          isSubmitting: _isSubmitting,
          onBack: () => setState(() => _docSubStep = 3),
          error: _error,
        );
    }
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
/// things to avoid, an Upload button, and Next (disabled until
/// uploaded). Reused for all 3 documents (Identity Card / Driving
/// License / Road Tax) in _buildDocumentsStep, since the layout is
/// identical for each — only the copy, sample image, and callbacks
/// differ.
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
  final VoidCallback? onNext; // null = disabled (not yet uploaded)
  final VoidCallback onBack;
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

/// Declarations (Pengisytiharan) — 5 plain-text checkboxes, all
/// required before Consents. No links here (unlike _ConsentsStep) —
/// these are statements the rider affirms, not documents to review.
class _DeclarationsStep extends StatelessWidget {
  const _DeclarationsStep({
    required this.decl1,
    required this.decl2,
    required this.decl3,
    required this.decl4,
    required this.decl5,
    required this.onChanged1,
    required this.onChanged2,
    required this.onChanged3,
    required this.onChanged4,
    required this.onChanged5,
    required this.onNext,
    required this.onBack,
  });

  final bool decl1, decl2, decl3, decl4, decl5;
  final ValueChanged<bool> onChanged1, onChanged2, onChanged3, onChanged4, onChanged5;
  final VoidCallback? onNext;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final items = [
      (decl1, onChanged1, 'Saya tidak pernah disabitkan dalam mana-mana kes mahkamah.'),
      (
        decl2,
        onChanged2,
        'Saya berjanji untuk mengendalikan kenderaan saya dengan selamat dan '
            'mematuhi semua undang-undang lalu lintas jalan raya Malaysia pada '
            'setiap masa.'
      ),
      (
        decl3,
        onChanged3,
        'Saya tidak mempunyai sebarang keadaan kesihatan yang mungkin '
            'menyebabkan saya tidak dapat memandu/menunggang dengan selamat.'
      ),
      (
        decl4,
        onChanged4,
        'Saya membenarkan LB Pickup and Delivery dan ejen atau wakilnya untuk '
            'menjalankan semakan latar belakang terhadap saya untuk tujuan '
            'permohonan sebagai rakan penghantar.'
      ),
      (
        decl5,
        onChanged5,
        'Saya dengan ini mengisytiharkan bahawa semua maklumat, butiran '
            'pengenalan diri, rekod lesen memandu, dan dokumen kenderaan yang '
            'dikemukakan dalam permohonan ini adalah benar, tepat, dan terkini.'
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

/// Consents (Persetujuan) — 4 checkboxes, each with a tappable link to
/// its policy page, all required before OTP is sent.
class _ConsentsStep extends StatelessWidget {
  const _ConsentsStep({
    required this.consent1,
    required this.consent2,
    required this.consent3,
    required this.consent4,
    required this.onChanged1,
    required this.onChanged2,
    required this.onChanged3,
    required this.onChanged4,
    required this.privacyNoticeRecognizer,
    required this.deliveryTermsRecognizer,
    required this.paymentTermsRecognizer,
    required this.codeOfConductRecognizer,
    required this.onNext,
    required this.onBack,
    this.isSubmitting = false,
    this.error,
  });

  final bool consent1, consent2, consent3, consent4;
  final ValueChanged<bool> onChanged1, onChanged2, onChanged3, onChanged4;
  final TapGestureRecognizer privacyNoticeRecognizer;
  final TapGestureRecognizer deliveryTermsRecognizer;
  final TapGestureRecognizer paymentTermsRecognizer;
  final TapGestureRecognizer codeOfConductRecognizer;
  final VoidCallback? onNext;
  final VoidCallback onBack;
  final bool isSubmitting;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = [
      (consent1, onChanged1, 'Notis Privasi', privacyNoticeRecognizer),
      (consent2, onChanged2, 'Terms of Service - Transport, Delivery and Logistics', deliveryTermsRecognizer),
      (consent3, onChanged3, 'Terms of Service - Payment and Rewards', paymentTermsRecognizer),
      (consent4, onChanged4, 'Code of Conduct - Driver and Delivery Partner Guidelines', codeOfConductRecognizer),
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
