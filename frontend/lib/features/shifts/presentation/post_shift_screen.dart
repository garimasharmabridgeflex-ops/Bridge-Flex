import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/constants/profile_options.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/chip_multi_select.dart';
import '../../billing/presentation/nursery_subscription_card.dart';
import '../../onboarding/presentation/widgets/onboarding_illustration.dart';
import '../../onboarding/presentation/widgets/wizard_scaffold.dart';
import '../../profile/domain/branch.dart';
import '../../profile/domain/profile.dart';
import '../../profile/presentation/branches_screen.dart';

/// Posting a shift as a 3-step wizard (Shift details → Care details → Pay &
/// publish) — reuses the same [WizardStepScaffold] chrome the onboarding
/// wizards use, mirroring the reference design's multi-step "Create Job"
/// flow instead of one long scrolling form.
class PostShiftScreen extends ConsumerStatefulWidget {
  const PostShiftScreen({super.key});

  @override
  ConsumerState<PostShiftScreen> createState() => _PostShiftScreenState();
}

class _PostShiftScreenState extends ConsumerState<PostShiftScreen> {
  final _pageController = PageController();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _payRate = TextEditingController();
  final _room = TextEditingController();
  final _numberOfChildren = TextEditingController();
  final _safeguardingNotes = TextEditingController();
  final _healthAndSafetyNotes = TextEditingController();

  int _capacity = 1;
  int _unpaidBreakMinutes = 30;
  String _requiredQualification = 'level_3';
  String? _selectedBranchId;
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  TimeOfDay _startTime = const TimeOfDay(hour: 9, minute: 0);
  TimeOfDay _endTime = const TimeOfDay(hour: 17, minute: 0);
  bool _loading = false;
  String _ageGroup = ageGroupOptions.first;
  List<String> _expectedDuties = [];
  List<String> _requirements = [];

  @override
  void initState() {
    super.initState();
    _title.addListener(_rebuild);
    _payRate.addListener(_rebuild);
  }

  void _rebuild() => setState(() {});

  @override
  void dispose() {
    _pageController.dispose();
    _title.removeListener(_rebuild);
    _payRate.removeListener(_rebuild);
    _title.dispose();
    _description.dispose();
    _payRate.dispose();
    _room.dispose();
    _numberOfChildren.dispose();
    _safeguardingNotes.dispose();
    _healthAndSafetyNotes.dispose();
    super.dispose();
  }

  DateTime get _startDateTime =>
      DateTime(_date.year, _date.month, _date.day, _startTime.hour, _startTime.minute);
  DateTime get _endDateTime =>
      DateTime(_date.year, _date.month, _date.day, _endTime.hour, _endTime.minute);

  bool get _detailsValid => _title.text.trim().isNotEmpty;
  bool get _payValid {
    final n = double.tryParse(_payRate.text);
    return n != null && n > 0;
  }

  void _goTo(int step) {
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime({required bool isStart}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: isStart ? _startTime : _endTime,
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startTime = picked;
      } else {
        _endTime = picked;
      }
    });
  }

  Future<void> _publish() async {
    if (!_endDateTime.isAfter(_startDateTime)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('End time must be after start time')));
      return;
    }
    setState(() => _loading = true);
    try {
      final shiftId = await ref.read(shiftRepositoryProvider).createShift(
            title: _title.text.trim(),
            description: _description.text.trim(),
            capacity: _capacity,
            date: DateFormat('yyyy-MM-dd').format(_date),
            startTime: _startDateTime,
            endTime: _endDateTime,
            payRate: double.parse(_payRate.text),
            ageGroup: _ageGroup,
            room: _room.text.trim(),
            numberOfChildren: int.tryParse(_numberOfChildren.text.trim()) ?? 0,
            expectedDuties: _expectedDuties,
            requirements: _requirements,
            branchId: _selectedBranchId ?? '',
            requiredQualification: _requiredQualification,
            unpaidBreakMinutes: _unpaidBreakMinutes,
            safeguardingNotes: _safeguardingNotes.text.trim(),
            healthAndSafetyNotes: _healthAndSafetyNotes.text.trim(),
          );
      if (mounted) {
        context.pushReplacement('/shifts/$shiftId');
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildBlockedScaffold(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Post Shift'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.pop(),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
                side: const BorderSide(color: Color(0xFFE2E8F0)),
              ),
              elevation: 0,
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 36),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: iconColor, size: 36),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1B2A4A),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF64748B),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: onAction,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF1B2A4A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: Text(
                          actionLabel,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final subAsync = ref.watch(nurserySubscriptionProvider);

    if (profile != null && profile.role == UserRole.nursery) {
      final status = profile.nurseryApprovalStatus.toLowerCase().trim();
      if (status != 'approved') {
        if (status == 'rejected') {
          return _buildBlockedScaffold(
            context,
            icon: Icons.highlight_off_rounded,
            iconColor: const Color(0xFFDC2626),
            title: 'Nursery Verification Issue',
            message:
                'Your nursery registration has not been approved. Please review your settings or contact support for assistance.',
            actionLabel: 'Edit Nursery Profile',
            onAction: () => context.push('/profile/edit'),
          );
        }
        return _buildBlockedScaffold(
          context,
          icon: Icons.hourglass_top_rounded,
          iconColor: const Color(0xFFD97706),
          title: 'Account Verification Required',
          message:
              'Your nursery registration is currently being verified by our compliance team. Once verified, you will receive your 14-day free trial and will be able to post shifts and book qualified practitioners.',
          actionLabel: 'Return to Dashboard',
          onAction: () => context.go('/'),
        );
      }

      final subData = subAsync.valueOrNull;
      if (subData != null) {
        final isTrialExpired =
            subData.subscription.isTrialing && subData.trial.isExpired;
        final isSubExpired = subData.subscription.isExpired;
        if (isTrialExpired || isSubExpired) {
          return _buildBlockedScaffold(
            context,
            icon: Icons.card_membership_rounded,
            iconColor: const Color(0xFF2563EB),
            title: 'Membership Required to Post Shifts',
            message:
                'Your 14-day free trial has expired. To post new shifts and access our verified practitioner pool, please activate a membership plan or choose pay-as-you-go.',
            actionLabel: 'View Membership Plans',
            onAction: () => context.push('/billing/subscriptions'),
          );
        }
      }
    }

    final totalMinutes = _endDateTime.difference(_startDateTime).inMinutes;
    final payableMinutes = (totalMinutes - _unpaidBreakMinutes).clamp(0, totalMinutes);
    final payableHours = (payableMinutes / 60.0).toStringAsFixed(1);
    final branches = ref.watch(branchesProvider).valueOrNull ?? const <Branch>[];

    return Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          // ── Step 1: Shift details ────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 0,
            stepCount: 3,
            title: 'Shift details',
            subtitle: 'When, and how many staff you need.',
            illustration: const OnboardingIllustration(
              icon: Icons.event_note_rounded,
              color: AppColors.indigo,
              satellites: [Icons.schedule_rounded, Icons.groups_rounded],
              size: 120,
            ),
            canContinue: _detailsValid,
            nextLabel: 'Next',
            onNext: () => _goTo(1),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Shift title',
                  controller: _title,
                  prefixIcon: Icons.title_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Shift Setting / Location',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF1B2A4A),
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await context.push('/profile/branches');
                              ref.invalidate(branchesProvider);
                            },
                            icon: const Icon(Icons.add_location_alt_outlined, size: 16),
                            label: const Text('Manage Branches', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              foregroundColor: const Color(0xFF2563EB),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        value: _selectedBranchId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                          ),
                          prefixIcon: const Icon(Icons.storefront_outlined, color: Color(0xFF2563EB)),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Main Setting / Primary Location', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                          ),
                          ...branches.map((b) => DropdownMenuItem(
                                value: b.id,
                                child: Text('${b.name} (${b.postcode})', style: const TextStyle(fontSize: 13.5)),
                              )),
                        ],
                        onChanged: (v) => setState(() => _selectedBranchId = v),
                      ),
                      if (_selectedBranchId != null) ...[
                        const SizedBox(height: 6),
                        Builder(
                          builder: (context) {
                            final b = branches.where((x) => x.id == _selectedBranchId).firstOrNull;
                            if (b == null) return const SizedBox.shrink();
                            return Text(
                              '📍 ${b.address}, ${b.postcode}',
                              style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Shift overview & notes (optional)',
                  controller: _description,
                  maxLines: 2,
                  prefixIcon: Icons.notes_rounded,
                ),
                const SizedBox(height: AppSpacing.md),
                Text('Staff needed', style: Theme.of(context).textTheme.labelMedium),
                const SizedBox(height: 4),
                Row(
                  children: [
                    IconButton.filledTonal(
                      onPressed: _capacity > 1 ? () => setState(() => _capacity--) : null,
                      icon: const Icon(Icons.remove_rounded, size: 18),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text(
                        '$_capacity ${_capacity == 1 ? 'staff member' : 'staff members'}',
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                    ),
                    IconButton.filledTonal(
                      onPressed: () => setState(() => _capacity++),
                      icon: const Icon(Icons.add_rounded, size: 18),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _PickerTile(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date',
                  value: DateFormat('EEE d MMMM yyyy').format(_date),
                  onTap: _pickDate,
                ),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(
                      child: _PickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'Start time',
                        value: _startTime.format(context),
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _PickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'End time',
                        value: _endTime.format(context),
                        onTap: () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Unpaid break duration', style: Theme.of(context).textTheme.labelMedium),
                    Text(
                      _unpaidBreakMinutes == 0 ? 'No break' : '$_unpaidBreakMinutes mins unpaid',
                      style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2563EB), fontSize: 12.5),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [0, 15, 30, 45, 60].map((mins) {
                    final isSelected = _unpaidBreakMinutes == mins;
                    return ChoiceChip(
                      label: Text(mins == 0 ? 'None (0m)' : '${mins}m'),
                      selected: isSelected,
                      onSelected: (_) => setState(() => _unpaidBreakMinutes = mins),
                      selectedColor: const Color(0xFF2563EB).withValues(alpha: 0.15),
                      labelStyle: TextStyle(
                        color: isSelected ? const Color(0xFF2563EB) : const Color(0xFF475569),
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    );
                  }).toList(),
                ),
                Container(
                  margin: const EdgeInsets.only(top: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: Color(0xFF64748B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Total working time: $payableHours hrs (Break deducted from gross hours)',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569), fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Step 2: Care & Compliance ────────────────────────────────
          WizardStepScaffold(
            stepIndex: 1,
            stepCount: 3,
            title: 'Care & compliance',
            subtitle: 'Qualifications, duties, and safety instructions.',
            illustration: const OnboardingIllustration(
              icon: Icons.child_care_rounded,
              color: AppColors.mint,
              satellites: [Icons.checklist_rounded, Icons.stairs_rounded],
              size: 120,
            ),
            canContinue: true,
            nextLabel: 'Next',
            onNext: () => _goTo(2),
            onBack: () => _goTo(0),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DropdownButtonFormField<String>(
                  value: _requiredQualification,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Minimum Required Qualification',
                    prefixIcon: Icon(Icons.school_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'level_3', child: Text('Level 3 (Early Years Educator) — Standard')),
                    DropdownMenuItem(value: 'level_2', child: Text('Level 2 (Early Years Assistant)')),
                    DropdownMenuItem(value: 'level_4_plus', child: Text('Level 4+ / Degree / EYTS / QTS')),
                    DropdownMenuItem(value: 'none', child: Text('Unqualified / Any experience level')),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => _requiredQualification = v);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  initialValue: _ageGroup,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Age group',
                    prefixIcon: Icon(Icons.child_care_rounded),
                  ),
                  items: ageGroupOptions
                      .map((g) => DropdownMenuItem(
                            value: g,
                            child: Text(g, overflow: TextOverflow.ellipsis),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _ageGroup = v);
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Room name (e.g. Baby Room)',
                        controller: _room,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppTextField(
                        label: 'Number of children',
                        controller: _numberOfChildren,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Expected duties', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                ChipMultiSelect(
                  options: shiftDutyOptions,
                  selected: _expectedDuties,
                  onChanged: (v) => setState(() => _expectedDuties = v),
                  allowCustom: true,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Special requirements', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                ChipMultiSelect(
                  options: shiftRequirementOptions,
                  selected: _requirements,
                  onChanged: (v) => setState(() => _requirements = v),
                  allowCustom: true,
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('Compliance & Check-in Details', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                AppTextField(
                  label: 'Safeguarding & check-in procedure (optional)',
                  controller: _safeguardingNotes,
                  maxLines: 2,
                  prefixIcon: Icons.shield_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Health & safety guidelines (optional)',
                  controller: _healthAndSafetyNotes,
                  maxLines: 2,
                  prefixIcon: Icons.health_and_safety_outlined,
                ),
              ],
            ),
          ),

          // ── Step 3: Pay & publish ────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 2,
            stepCount: 3,
            title: 'Pay & publish',
            subtitle: 'Review shift calculation and publish live.',
            illustration: const OnboardingIllustration(
              icon: Icons.payments_rounded,
              color: AppColors.coral,
              satellites: [Icons.publish_rounded, Icons.check_circle_rounded],
              size: 120,
            ),
            canContinue: _payValid,
            loading: _loading,
            nextLabel: 'Publish shift',
            onNext: _publish,
            onBack: () => _goTo(1),
            body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Pay rate (£/hour)',
                  controller: _payRate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  prefixIcon: Icons.payments_outlined,
                ),
                const SizedBox(height: AppSpacing.md),
                Builder(
                  builder: (context) {
                    final rate = double.tryParse(_payRate.text) ?? 0.0;
                    final grossPay = rate * (payableMinutes / 60.0);
                    final holidayPay = grossPay * 0.1207;
                    final totalEst = grossPay + holidayPay;

                    return Container(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.calculate_outlined, size: 18, color: Color(0xFF2563EB)),
                              SizedBox(width: 8),
                              Text('Pay Calculation Preview', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                            ],
                          ),
                          const Divider(height: 20),
                          _calcRow('Shift duration', '${totalMinutes ~/ 60}h ${totalMinutes % 60}m'),
                          _calcRow('Unpaid break', '-$_unpaidBreakMinutes mins'),
                          _calcRow('Payable working hours', '$payableHours hrs', isBold: true),
                          const SizedBox(height: 4),
                          _calcRow('Practitioner basic pay', '£${grossPay.toStringAsFixed(2)}'),
                          _calcRow('Statutory holiday pay (12.07%)', '£${holidayPay.toStringAsFixed(2)}'),
                          const Divider(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Est. Practitioner Total', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5)),
                              Text(
                                '£${totalEst.toStringAsFixed(2)}',
                                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Color(0xFF2563EB)),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(context, [
                  _summaryRow(context, 'Title', _title.text.trim().isEmpty ? '—' : _title.text.trim()),
                  _summaryRow(
                    context,
                    'Location',
                    _selectedBranchId != null
                        ? branches
                                .where((b) => b.id == _selectedBranchId)
                                .map((b) => '${b.name} (${b.postcode})')
                                .firstOrNull ??
                            'Branch Location'
                        : 'Main Setting / Primary Location',
                  ),
                  _summaryRow(context, 'When',
                      '${DateFormat('EEE d MMM').format(_date)}, ${_startTime.format(context)}–${_endTime.format(context)}'),
                  _summaryRow(context, 'Break', '$_unpaidBreakMinutes mins unpaid'),
                  _summaryRow(context, 'Staff needed', '$_capacity practitioner${_capacity == 1 ? '' : 's'}'),
                  _summaryRow(context, 'Age group', _ageGroup),
                  _summaryRow(context, 'Qualification', _requiredQualification.replaceAll('_', ' ').toUpperCase()),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _calcRow(String label, String value, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: const Color(0xFF64748B), fontWeight: isBold ? FontWeight.w700 : FontWeight.w400)),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: isBold ? FontWeight.w700 : FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _sectionCard(BuildContext context, List<Widget> rows) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: rows),
    );
  }

  Widget _summaryRow(BuildContext context, String label, String value) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant)),
                  Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
