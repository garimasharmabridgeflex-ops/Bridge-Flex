import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/constants/profile_options.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/chip_multi_select.dart';
import '../../../shared/widgets/primary_button.dart';

class PostShiftScreen extends ConsumerStatefulWidget {
  const PostShiftScreen({super.key});

  @override
  ConsumerState<PostShiftScreen> createState() => _PostShiftScreenState();
}

class _PostShiftScreenState extends ConsumerState<PostShiftScreen> {
  final _formKey = GlobalKey<FormState>();
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
  void dispose() {
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

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
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
      appBar: AppBar(title: const Text('Post a shift')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppTextField(
                  label: 'Shift title',
                  controller: _title,
                  prefixIcon: Icons.title_rounded,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ).animate().fadeIn(duration: 250.ms),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Shift details & requirements (optional)',
                  controller: _description,
                  maxLines: 3,
                  prefixIcon: Icons.notes_rounded,
                ).animate().fadeIn(delay: 40.ms, duration: 250.ms),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Staff needed', style: Theme.of(context).textTheme.labelMedium),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              IconButton.filledTonal(
                                onPressed: _capacity > 1
                                    ? () => setState(() => _capacity--)
                                    : null,
                                icon: const Icon(Icons.remove_rounded, size: 18),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('$_capacity', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                              ),
                              IconButton.filledTonal(
                                onPressed: () => setState(() => _capacity++),
                                icon: const Icon(Icons.add_rounded, size: 18),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                _PickerTile(
                  icon: Icons.calendar_today_rounded,
                  label: 'Date',
                  value: DateFormat('EEE d MMMM yyyy').format(_date),
                  onTap: _pickDate,
                ).animate().fadeIn(delay: 50.ms, duration: 250.ms),
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
                ).animate().fadeIn(delay: 100.ms, duration: 250.ms),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  label: 'Pay rate (£/hour)',
                  controller: _payRate,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  prefixIcon: Icons.payments_outlined,
                  validator: (v) {
                    if (v == null || v.isEmpty) return 'Required';
                    final n = double.tryParse(v);
                    if (n == null || n <= 0) return 'Enter a valid rate';
                    return null;
                  },
                ).animate().fadeIn(delay: 150.ms, duration: 250.ms),
                const SizedBox(height: AppSpacing.lg),
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
                        label: 'Room (optional)',
                        controller: _room,
                        prefixIcon: Icons.door_front_door_outlined,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: AppTextField(
                        label: 'Number of children',
                        controller: _numberOfChildren,
                        keyboardType: TextInputType.number,
                        prefixIcon: Icons.groups_outlined,
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
                const SizedBox(height: AppSpacing.xl),
                PrimaryButton(
                  label: 'Publish shift',
                  icon: Icons.publish_rounded,
                  loading: _loading,
                  onPressed: _submit,
                ).animate().fadeIn(delay: 200.ms, duration: 250.ms),
              ],
            ),
          ),
        ),
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
