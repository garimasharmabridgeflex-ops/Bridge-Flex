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

  final _descriptionController = TextEditingController();
  final _hoursController = TextEditingController();
  OfstedRating _ofsted = OfstedRating.notRated;

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
    super.dispose();
  }

  bool get _basicsValid =>
      _nameController.text.trim().isNotEmpty &&
      _addressController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty;

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
            stepCount: 2,
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
            stepCount: 2,
            title: 'About the setting',
            subtitle: 'A real description helps staff say yes with confidence.',
            illustration: const OnboardingIllustration(
              icon: Icons.auto_stories_rounded,
              color: AppColors.mint,
              satellites: [Icons.star_rounded, Icons.schedule_rounded],
            ),
            canContinue: true,
            loading: _saving,
            nextLabel: 'Finish',
            onNext: _saveAbout,
            onSkip: () => context.go('/home'),
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
        ],
      ),
    );
  }
}
