import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/phone_field.dart';
import '../../profile/domain/profile.dart';
import 'widgets/onboarding_illustration.dart';
import 'widgets/wizard_scaffold.dart';

/// Nursery profile setup wizard — full app spec §1.3. Basics saves
/// immediately on "Next" (the router's hard gate, §1.4); "About the
/// setting" is save-and-continue / skippable.
class NurseryOnboardingScreen extends ConsumerStatefulWidget {
  const NurseryOnboardingScreen({super.key});

  @override
  ConsumerState<NurseryOnboardingScreen> createState() =>
      _NurseryOnboardingScreenState();
}

class _NurseryOnboardingScreenState
    extends ConsumerState<NurseryOnboardingScreen> {
  final _pageController = PageController();
  bool _saving = false;

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  String _fullPhone = '+44 ';
  bool _phoneValid = true;

  final _descriptionController = TextEditingController();
  final _hoursController = TextEditingController();
  OfstedRating _ofsted = OfstedRating.notRated;

  // Step 3: Registration & Compliance additions (Phase 5)
  final _companyNumberController = TextEditingController();
  final _locationCountController = TextEditingController(text: '1');
  final _billingAddressController = TextEditingController();
  final _billingEmailController = TextEditingController();
  final _billingContactController = TextEditingController();
  final _staffingReqController = TextEditingController();
  String _paymentMethod = 'bank_transfer';

  @override
  void initState() {
    super.initState();
    final profile = ref.read(ownProfileProvider).valueOrNull;
    if (profile != null) {
      _nameController.text = profile.name;
      _addressController.text = profile.address;
      final (dialCode, local) = splitPhone(profile.phone);
      _phoneController.text = local;
      _fullPhone = profile.phone.isNotEmpty ? profile.phone : '$dialCode ';
      _descriptionController.text = profile.description;
      _hoursController.text = profile.openingHours;
      _ofsted = profile.ofstedRating;
      _companyNumberController.text = profile.companyNumber;
      _locationCountController.text = profile.locationCount > 0 ? profile.locationCount.toString() : '1';
      _billingAddressController.text = profile.billingAddress;
      _billingEmailController.text = profile.billingEmail;
      _billingContactController.text = profile.billingContactPerson;
      _staffingReqController.text = profile.staffingRequirements;
      if (profile.preferredPaymentMethod.isNotEmpty) {
        _paymentMethod = profile.preferredPaymentMethod;
      }
    }

    // Listeners so canContinue re-evaluates on every keystroke.
    _nameController.addListener(_rebuild);
    _addressController.addListener(_rebuild);
    _phoneController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.removeListener(_rebuild);
    _addressController.removeListener(_rebuild);
    _phoneController.removeListener(_rebuild);
    _nameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _descriptionController.dispose();
    _hoursController.dispose();
    _companyNumberController.dispose();
    _locationCountController.dispose();
    _billingAddressController.dispose();
    _billingEmailController.dispose();
    _billingContactController.dispose();
    _staffingReqController.dispose();
    super.dispose();
  }

  bool get _basicsValid =>
      _nameController.text.trim().isNotEmpty &&
      _addressController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty &&
      _phoneValid;

  void _goTo(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _detectLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.medium),
      );
      await ref.read(profileRepositoryProvider).updateProfile(
            lat: pos.latitude,
            lng: pos.longitude,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'Location set: ${pos.latitude.toStringAsFixed(3)}, ${pos.longitude.toStringAsFixed(3)}'),
        ));
      }
    } catch (_) {}
  }

  Future<void> _saveBasics() async {
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            name: _nameController.text.trim(),
            address: _addressController.text.trim(),
            phone: _fullPhone.trim(),
          );
      ref.invalidate(ownProfileProvider);
      if (mounted) _goTo(1);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAbout() async {
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            description: _descriptionController.text.trim(),
            openingHours: _hoursController.text.trim(),
            ofstedRating: _ofsted,
          );
      ref.invalidate(ownProfileProvider);
      if (mounted) _goTo(2);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveRegistration() async {
    setState(() => _saving = true);
    try {
      final locCount = int.tryParse(_locationCountController.text.trim()) ?? 1;
      await ref.read(profileRepositoryProvider).updateProfile(
            companyNumber: _companyNumberController.text.trim(),
            locationCount: locCount,
            preferredPaymentMethod: _paymentMethod,
            billingAddress: _billingAddressController.text.trim().isNotEmpty
                ? _billingAddressController.text.trim()
                : _addressController.text.trim(),
            billingEmail: _billingEmailController.text.trim(),
            billingContactPerson: _billingContactController.text.trim().isNotEmpty
                ? _billingContactController.text.trim()
                : _nameController.text.trim(),
            staffingRequirements: _staffingReqController.text.trim(),
          );
      ref.invalidate(ownProfileProvider);
      if (mounted) context.go('/home');
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // ── Step 1: Basics ────────────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 0,
            stepCount: 3,
            title: 'Tell us about your nursery',
            subtitle: 'Staff see this before they accept a shift.',
            illustration: const OnboardingIllustration(
              icon: Icons.home_work_rounded,
              color: AppColors.indigo,
              satellites: [Icons.phone_rounded, Icons.location_on_rounded],
            ),
            canContinue: _basicsValid,
            loading: _saving,
            nextLabel: 'Next',
            onNext: _saveBasics,
            body: Column(
              children: [
                AppTextField(
                  label: 'Nursery name',
                  controller: _nameController,
                  prefixIcon: Icons.home_work_outlined,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Address',
                  controller: _addressController,
                  prefixIcon: Icons.place_outlined,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                PhoneField(
                  controller: _phoneController,
                  initialDialCode: '+44',
                  textInputAction: TextInputAction.done,
                  onChanged: (full) => setState(() => _fullPhone = full),
                  onValidityChanged: (valid) =>
                      setState(() => _phoneValid = valid),
                ),
                const SizedBox(height: AppSpacing.md),
                OutlinedButton.icon(
                  onPressed: _detectLocation,
                  icon: const Icon(Icons.my_location_rounded),
                  label: const Text('Detect nursery location (GPS)'),
                ),
              ],
            ),
          ),

          // ── Step 2: About the setting ─────────────────────────────────
          WizardStepScaffold(
            stepIndex: 1,
            stepCount: 3,
            title: 'About the setting',
            subtitle: 'A real description helps staff say yes with confidence.',
            illustration: const OnboardingIllustration(
              icon: Icons.auto_stories_rounded,
              color: AppColors.mint,
              satellites: [Icons.star_rounded, Icons.schedule_rounded],
            ),
            canContinue: true,
            loading: _saving,
            nextLabel: 'Next',
            onNext: _saveAbout,
            onSkip: () => _goTo(2),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Description',
                  controller: _descriptionController,
                  maxLines: 4,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Opening hours (optional)',
                  controller: _hoursController,
                  prefixIcon: Icons.schedule_outlined,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Ofsted rating (optional)',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: OfstedRating.values.map((rating) {
                    final selected = rating == _ofsted;
                    return ChoiceChip(
                      label: Text(ofstedRatingLabel(rating)),
                      selected: selected,
                      onSelected: (_) => setState(() => _ofsted = rating),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),

          // ── Step 3: Registration & Compliance ─────────────────────────
          WizardStepScaffold(
            stepIndex: 2,
            stepCount: 3,
            title: 'Registration & Billing',
            subtitle: 'Official business details for invoicing and admin verification.',
            illustration: const OnboardingIllustration(
              icon: Icons.domain_verification_rounded,
              color: AppColors.coral,
              satellites: [Icons.receipt_long_rounded, Icons.apartment_rounded],
            ),
            canContinue: true,
            loading: _saving,
            nextLabel: 'Complete Registration',
            onNext: _saveRegistration,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Company number (optional)',
                  controller: _companyNumberController,
                  prefixIcon: Icons.numbers_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Number of locations / branches',
                  controller: _locationCountController,
                  prefixIcon: Icons.account_tree_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Preferred payment method',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('Bank Transfer (BACS)'),
                      selected: _paymentMethod == 'bank_transfer',
                      onSelected: (_) => setState(() => _paymentMethod = 'bank_transfer'),
                    ),
                    ChoiceChip(
                      label: const Text('Direct Debit'),
                      selected: _paymentMethod == 'direct_debit',
                      onSelected: (_) => setState(() => _paymentMethod = 'direct_debit'),
                    ),
                    ChoiceChip(
                      label: const Text('Card'),
                      selected: _paymentMethod == 'card',
                      onSelected: (_) => setState(() => _paymentMethod = 'card'),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'Billing address (if different)',
                  controller: _billingAddressController,
                  prefixIcon: Icons.location_city_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Billing contact email',
                  controller: _billingEmailController,
                  prefixIcon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Staffing requirements / ratio notes',
                  controller: _staffingReqController,
                  prefixIcon: Icons.groups_rounded,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ],
      ),
    );
          ),
        ],
      ),
    );
  }
}
