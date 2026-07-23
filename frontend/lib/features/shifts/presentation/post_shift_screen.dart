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
import '../../onboarding/presentation/widgets/onboarding_illustration.dart';
import '../../onboarding/presentation/widgets/wizard_scaffold.dart';

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
  int _capacity = 1;
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
    // _detailsValid/_payValid read straight from these controllers, so
    // without a rebuild on every keystroke, canContinue/Publish never
    // re-evaluates and the button just looks permanently disabled.
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

  @override
  Widget build(BuildContext context) {
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
                AppTextField(
                  label: 'Shift details & requirements (optional)',
                  controller: _description,
                  maxLines: 3,
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
                        label: 'Start',
                        value: _startTime.format(context),
                        onTap: () => _pickTime(isStart: true),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: _PickerTile(
                        icon: Icons.schedule_rounded,
                        label: 'End',
                        value: _endTime.format(context),
                        onTap: () => _pickTime(isStart: false),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Step 2: Care details ─────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 1,
            stepCount: 3,
            title: 'Care details',
            subtitle: 'Helps staff know exactly what the shift involves.',
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
                Text('Age group', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: ageGroupOptions.map((g) {
                    return ChoiceChip(
                      label: Text(g),
                      selected: g == _ageGroup,
                      onSelected: (_) => setState(() => _ageGroup = g),
                    );
                  }).toList(),
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        label: 'Room',
                        controller: _room,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppTextField(
                        label: 'Children',
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
                Text('Minimum requirements', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                ChipMultiSelect(
                  options: shiftRequirementOptions,
                  selected: _requirements,
                  onChanged: (v) => setState(() => _requirements = v),
                  allowCustom: true,
                ),
              ],
            ),
          ),

          // ── Step 3: Pay & publish ────────────────────────────────────
          WizardStepScaffold(
            stepIndex: 2,
            stepCount: 3,
            title: 'Pay & publish',
            subtitle: 'Set the rate and post it live.',
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
                const SizedBox(height: AppSpacing.lg),
                _sectionCard(context, [
                  _summaryRow(context, 'Title', _title.text.trim().isEmpty ? '—' : _title.text.trim()),
                  _summaryRow(context, 'When',
                      '${DateFormat('EEE d MMM').format(_date)}, ${_startTime.format(context)}–${_endTime.format(context)}'),
                  _summaryRow(context, 'Staff needed', '$_capacity'),
                  _summaryRow(context, 'Age group', _ageGroup),
                ]),
              ],
            ),
          ),
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
