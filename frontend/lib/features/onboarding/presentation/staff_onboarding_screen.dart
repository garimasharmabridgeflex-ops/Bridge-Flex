import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/phone_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../../profile/domain/profile.dart';
import 'widgets/onboarding_illustration.dart';
import 'widgets/wizard_scaffold.dart';

/// Staff profile setup wizard — full app spec §1.2. Basics saves
/// immediately on "Next" (that's the router's hard gate, §1.4); Experience
/// and the DBS step are save-and-continue / skippable, since only Basics
/// blocks entry to the app.
class StaffOnboardingScreen extends ConsumerStatefulWidget {
  const StaffOnboardingScreen({super.key});

  @override
  ConsumerState<StaffOnboardingScreen> createState() =>
      _StaffOnboardingScreenState();
}

class _StaffOnboardingScreenState
    extends ConsumerState<StaffOnboardingScreen> {
  final _pageController = PageController();
  bool _saving = false;

  // Step 1: Basics
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();

  // The full phone string (dialCode + local), kept in sync by PhoneField.
  String _fullPhone = '+44 ';
  bool _phoneValid = true;

  // Step 2: Experience
  int _yearsExperience = 0;
  QualificationLevel _qualification = QualificationLevel.none;
  final _bioController = TextEditingController();

  @override
  void initState() {
    super.initState();

    // ── Pre-populate from existing profile ─────────────────────────────
    final profile = ref.read(ownProfileProvider).valueOrNull;
    if (profile != null) {
      _nameController.text = profile.name;
      final (dialCode, local) = splitPhone(profile.phone);
      _phoneController.text = local;
      _fullPhone = profile.phone.isNotEmpty ? profile.phone : '$dialCode ';
      _yearsExperience = profile.yearsExperience;
      _qualification = profile.qualificationLevel;
      _bioController.text = profile.bio;
    }

    // ── Rebuild when text changes so canContinue re-evaluates ──────────
    _nameController.addListener(_rebuild);
    _phoneController.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.removeListener(_rebuild);
    _phoneController.removeListener(_rebuild);
    _nameController.dispose();
    _phoneController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  // "Next" is enabled only when both required fields have content.
  bool get _basicsValid =>
      _nameController.text.trim().isNotEmpty &&
      _phoneController.text.trim().isNotEmpty &&
      _phoneValid;

  void _goTo(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _saveBasics() async {
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            name: _nameController.text.trim(),
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

  Future<void> _saveExperience() async {
    setState(() => _saving = true);
    try {
      await ref.read(profileRepositoryProvider).updateProfile(
            yearsExperience: _yearsExperience,
            qualificationLevel: _qualification,
            bio: _bioController.text.trim(),
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

  void _finish() {
    // Basics is already saved and is the router's only hard gate — this
    // just lands them in the app; DBS can be finished later via the
    // profile-screen banner (full app spec §1.4).
    if (mounted) context.go('/home');
  }

  @override
  Widget build(BuildContext context) {
    final dbsStatus = ref.watch(ownProfileProvider).valueOrNull?.dbsStatus ?? DbsStatus.unverified;
    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // ── Step 1: Basics ────────────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 0,
            stepCount: 3,
            title: 'Tell us about you',
            subtitle: 'Nurseries see this before they book you.',
            illustration: const OnboardingIllustration(
              icon: Icons.badge_rounded,
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
                  label: 'Full name',
                  controller: _nameController,
                  prefixIcon: Icons.person_outline_rounded,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
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
                  label: const Text('Detect my location (GPS)'),
                ),
              ],
            ),
          ),

          // ── Step 2: Experience ────────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 1,
            stepCount: 3,
            title: 'Your experience',
            subtitle: 'Helps nurseries judge fit beyond a name and a DBS badge.',
            illustration: const OnboardingIllustration(
              icon: Icons.workspace_premium_rounded,
              color: AppColors.mint,
              satellites: [Icons.school_rounded, Icons.timeline_rounded],
            ),
            canContinue: true,
            loading: _saving,
            nextLabel: 'Next',
            onNext: _saveExperience,
            onSkip: () => _goTo(2),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Years of childcare experience',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                _StepperRow(
                  value: _yearsExperience,
                  onChanged: (v) => setState(() => _yearsExperience = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Qualification level',
                    style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: QualificationLevel.values.map((level) {
                    final selected = level == _qualification;
                    return ChoiceChip(
                      label: Text(qualificationLevelLabel(level)),
                      selected: selected,
                      onSelected: (_) =>
                          setState(() => _qualification = level),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.lg),
                AppTextField(
                  label: 'About me (optional)',
                  controller: _bioController,
                  maxLines: 3,
                ),
              ],
            ),
          ),

          // ── Step 3: Documents ────────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 2,
            stepCount: 3,
            title: 'Upload documents',
            subtitle:
                "You can browse shifts now, but you'll need your DBS and other checks verified to accept one.",
            illustration: const OnboardingIllustration(
              icon: Icons.verified_user_rounded,
              color: AppColors.coral,
              satellites: [Icons.shield_rounded, Icons.upload_file_rounded],
            ),
            canContinue: true,
            nextLabel: dbsStatus == DbsStatus.unverified ? "I'll do this later" : 'Continue',
            onNext: _finish,
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (dbsStatus == DbsStatus.unverified) ...[
                  const Text(
                    'Upload your DBS certificate, ID, qualifications and any other documents now, or skip and do it later from your profile.',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  PrimaryButton(
                    label: 'Upload documents',
                    icon: Icons.upload_file_outlined,
                    expand: true,
                    onPressed: () async {
                      await context.push('/profile/dbs');
                      ref.invalidate(ownProfileProvider);
                    },
                  ),
                ] else ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.mint.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.check_circle_rounded, color: AppColors.mint),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            dbsStatus == DbsStatus.verified
                                ? 'Your DBS certificate is verified.'
                                : 'Submitted — pending review.',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextButton.icon(
                    onPressed: () async {
                      await context.push('/profile/dbs');
                      ref.invalidate(ownProfileProvider);
                    },
                    icon: const Icon(Icons.upload_file_outlined, size: 18),
                    label: const Text('Manage documents'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Years stepper ────────────────────────────────────────────────────────────

class _StepperRow extends StatelessWidget {
  const _StepperRow({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton.filledTonal(
          onPressed: value > 0 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 56,
          child: Text(
            '$value ${value == 1 ? 'year' : 'years'}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        IconButton.filledTonal(
          onPressed: () => onChanged(value + 1),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}
