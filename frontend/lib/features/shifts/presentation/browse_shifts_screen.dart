import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../../shared/widgets/shimmer_box.dart';
import '../domain/shift.dart';
import 'widgets/shift_card.dart';

// ─── Providers ───────────────────────────────────────────────────────────────

final openShiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) {
  return ref.watch(shiftRepositoryProvider).fetchOpenShifts();
});

final _ownLocationAreaProvider = FutureProvider.autoDispose<String?>((
  ref,
) async {
  final uid = ref.watch(authStateProvider).valueOrNull?.uid;
  if (uid == null) return null;
  final profile = await ref
      .watch(profileRepositoryProvider)
      .fetchPublicProfile(uid);
  return profile?.locationArea;
});

// ─── Filter/Sort enums ────────────────────────────────────────────────────────

enum _DateFilter { any, today, thisWeek, pickDate }

enum _SortOrder { newest, soonest, highestPay }

extension _DateFilterLabel on _DateFilter {
  String get label => switch (this) {
    _DateFilter.any => 'Any date',
    _DateFilter.today => 'Today',
    _DateFilter.thisWeek => 'This week',
    _DateFilter.pickDate => 'Pick date…',
  };
}

extension _SortOrderLabel on _SortOrder {
  String get label => switch (this) {
    _SortOrder.newest => 'Newest posted',
    _SortOrder.soonest => 'Soonest first',
    _SortOrder.highestPay => 'Highest pay',
  };

  IconData get icon => switch (this) {
    _SortOrder.newest => Icons.fiber_new_rounded,
    _SortOrder.soonest => Icons.schedule_rounded,
    _SortOrder.highestPay => Icons.attach_money_rounded,
  };
}

// ─── Screen ───────────────────────────────────────────────────────────────────

class BrowseShiftsScreen extends ConsumerStatefulWidget {
  const BrowseShiftsScreen({super.key});

  @override
  ConsumerState<BrowseShiftsScreen> createState() => _BrowseShiftsScreenState();
}

class _BrowseShiftsScreenState extends ConsumerState<BrowseShiftsScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _showSearch = false;
  bool _nearMeOnly = false;
  _DateFilter _dateFilter = _DateFilter.any;
  DateTime? _pickedDate;
  double _minPayRate = 0;
  _SortOrder _sortOrder = _SortOrder.soonest;
  bool _showFilters = false;
  String? _categoryFilter;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _hasActiveFilters =>
      _nearMeOnly ||
      _dateFilter != _DateFilter.any ||
      _minPayRate > 0 ||
      _sortOrder != _SortOrder.soonest ||
      _categoryFilter != null;

  void _clearFilters() => setState(() {
    _nearMeOnly = false;
    _dateFilter = _DateFilter.any;
    _pickedDate = null;
    _minPayRate = 0;
    _sortOrder = _SortOrder.soonest;
    _categoryFilter = null;
  });

  List<Shift> _applyFilters(List<Shift> shifts, String? ownArea) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekEnd = todayStart.add(const Duration(days: 7));

    var filtered = shifts.where((s) {
      // Text search
      if (_query.isNotEmpty && !s.title.toLowerCase().contains(_query))
        return false;

      // Category (age group)
      if (_categoryFilter != null && s.ageGroup != _categoryFilter)
        return false;

      // Date filter
      switch (_dateFilter) {
        case _DateFilter.today:
          if (s.startTime.isBefore(todayStart) ||
              s.startTime.isAfter(todayStart.add(const Duration(days: 1)))) {
            return false;
          }
        case _DateFilter.thisWeek:
          if (s.startTime.isBefore(todayStart) ||
              s.startTime.isAfter(weekEnd)) {
            return false;
          }
        case _DateFilter.pickDate:
          if (_pickedDate != null) {
            final d = _pickedDate!;
            final dayStart = DateTime(d.year, d.month, d.day);
            final dayEnd = dayStart.add(const Duration(days: 1));
            if (s.startTime.isBefore(dayStart) || s.startTime.isAfter(dayEnd)) {
              return false;
            }
          }
        case _DateFilter.any:
          break;
      }

      // Min pay rate
      if (_minPayRate > 0 && s.payRate < _minPayRate) return false;

      // Near me filter (B1 fix: filter in _applyFilters so filtered.isEmpty is accurate)
      if (_nearMeOnly) {
        if (ownArea == null || ownArea.isEmpty) return false;
        if (s.nurseryArea != null && s.nurseryArea != ownArea) return false;
      }

      return true;
    }).toList();

    // Sort
    switch (_sortOrder) {
      case _SortOrder.newest:
        filtered.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _SortOrder.soonest:
        filtered.sort((a, b) => a.startTime.compareTo(b.startTime));
      case _SortOrder.highestPay:
        filtered.sort((a, b) => b.payRate.compareTo(a.payRate));
    }

    return filtered;
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDate ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        _dateFilter = _DateFilter.pickDate;
        _pickedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final shiftsAsync = ref.watch(openShiftsProvider);
    final ownAreaAsync = ref.watch(_ownLocationAreaProvider);
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final firstName = profile?.name.trim().split(' ').firstOrNull ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Top Utility Header (Stitch Alexandria Pattern) ───────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      // Left: Avatar with online badge
                      Stack(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFFE2E8F0),
                            backgroundImage: (profile?.photoUrl.isNotEmpty ?? false)
                                ? NetworkImage(profile!.photoUrl)
                                : null,
                            child: (profile == null || profile.photoUrl.isEmpty)
                                ? const Icon(Icons.person_rounded, color: Color(0xFF1B2A4A))
                                : null,
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: const Color(0xFF2563EB),
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Location & Greeting
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.location_on_rounded, color: Color(0xFF2563EB), size: 14),
                                const SizedBox(width: 3),
                                Text(
                                  ownAreaAsync.valueOrNull ?? 'Manchester, M1',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF64748B),
                                    letterSpacing: 0.3,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              firstName.isNotEmpty ? '${_greeting()}, $firstName' : _greeting(),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                                color: Color(0xFF0F172A),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      // Right action buttons: Search, Filters, Notifications
                      Row(
                        children: [
                          _CircularHeaderAction(
                            icon: Icons.search_rounded,
                            isActive: _showSearch || _query.isNotEmpty,
                            onTap: () => setState(() => _showSearch = !_showSearch),
                          ),
                          const SizedBox(width: 8),
                          _CircularHeaderAction(
                            icon: Icons.tune_rounded,
                            isActive: _hasActiveFilters,
                            badgeColor: const Color(0xFF2563EB),
                            onTap: () => setState(() => _showFilters = !_showFilters),
                          ),
                          const SizedBox(width: 8),
                          const NotificationIconButton(color: Color(0xFF1B2A4A)),
                        ],
                      ),
                    ],
                  ),
                  if (_showSearch) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        hintText: 'Search shifts, rooms, nurseries…',
                        hintStyle: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                        prefixIcon: const Icon(Icons.search_rounded, size: 18, color: Color(0xFF64748B)),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.5),
                        ),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.close_rounded, size: 16),
                                onPressed: () => setState(() {
                                  _searchController.clear();
                                  _query = '';
                                }),
                              ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Quick Category Pills (Stitch Alexandria Pattern) ─────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _QuickPill(
                      label: 'All Shifts',
                      count: shiftsAsync.valueOrNull?.length,
                      selected: _categoryFilter == null,
                      onTap: () => setState(() => _categoryFilter = null),
                    ),
                    const SizedBox(width: 8),
                    _QuickPill(
                      label: 'Urgent Cover',
                      dotColor: const Color(0xFF2563EB),
                      selected: _categoryFilter == 'Urgent Cover',
                      onTap: () => setState(() => _categoryFilter = _categoryFilter == 'Urgent Cover' ? null : 'Urgent Cover'),
                    ),
                    const SizedBox(width: 8),
                    _QuickPill(
                      label: 'Level 3 Qualified',
                      selected: _categoryFilter == 'Level 3 Qualified',
                      onTap: () => setState(() => _categoryFilter = _categoryFilter == 'Level 3 Qualified' ? null : 'Level 3 Qualified'),
                    ),
                    const SizedBox(width: 8),
                    _QuickPill(
                      label: 'Baby Room',
                      selected: _categoryFilter == 'Baby Room',
                      onTap: () => setState(() => _categoryFilter = _categoryFilter == 'Baby Room' ? null : 'Baby Room'),
                    ),
                  ],
                ),
              ),
            ),

            // ── Date Horizon Selector (Stitch Pattern) ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Select Date',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1B2A4A),
                        ),
                      ),
                      InkWell(
                        onTap: () => _pickDate(),
                        child: const Text(
                          'View Calendar',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF2563EB),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _DateHorizonSelector(
                    activeFilter: _dateFilter,
                    pickedDate: _pickedDate,
                    onSelect: (filter, date) => setState(() {
                      _dateFilter = filter;
                      _pickedDate = date;
                    }),
                  ),
                ],
              ),
            ),

            // ── Collapsible filter panel ─────────────────────────────────
            // ClipRect works around a well-known Flutter quirk: AnimatedSize
            // does a two-pass layout (an unconstrained probe, then the
            // animated constrained pass), and a SingleChildScrollView child
            // reports a sub-pixel-different height between the two passes —
            // harmless in practice, but without ClipRect it trips a debug-mode
            // "RenderFlex overflowed by 1.00 pixels" assertion.
            ClipRect(
              child: AnimatedSize(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: _showFilters
                    ? _FilterPanel(
                        nearMeOnly: _nearMeOnly,
                        ownAreaAsync: ownAreaAsync,
                        dateFilter: _dateFilter,
                        pickedDate: _pickedDate,
                        minPayRate: _minPayRate,
                        sortOrder: _sortOrder,
                        hasActiveFilters: _hasActiveFilters,
                        onNearMeToggle: (v) {
                          if (v && ownAreaAsync.valueOrNull == null) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please set your location in your profile to use the "Near me" filter.')),
                            );
                            return;
                          }
                          setState(() => _nearMeOnly = v);
                        },
                        onDateFilter: (f) async {
                          if (f == _DateFilter.pickDate) {
                            await _pickDate();
                          } else {
                            setState(() {
                              _dateFilter = f;
                              _pickedDate = null;
                            });
                          }
                        },
                        onPayRateChange: (v) => setState(() => _minPayRate = v),
                        onSortChange: (s) => setState(() => _sortOrder = s),
                        onClear: _clearFilters,
                      )
                    : const SizedBox.shrink(),
              ),
            ),

            // ── Quick-look active filter chips ────────────────────────────
            if (!_showFilters && _hasActiveFilters)
              _ActiveFilterChips(
                nearMeOnly: _nearMeOnly,
                dateFilter: _dateFilter,
                pickedDate: _pickedDate,
                minPayRate: _minPayRate,
                sortOrder: _sortOrder,
                onClear: _clearFilters,
              ),

            // ── Shift list ────────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(openShiftsProvider);
                  ref.invalidate(_ownLocationAreaProvider);
                },
                child: shiftsAsync.when(
                  loading: () => ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: 4,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, __) => const ShiftCardSkeleton(),
                  ),
                  error: (e, _) => ListView(
                    children: [
                      const SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.wifi_off_rounded,
                        title: "Couldn't load shifts",
                        subtitle: '$e',
                      ),
                    ],
                  ),
                  data: (shifts) {
                    final filtered = _applyFilters(
                      shifts,
                      ownAreaAsync.valueOrNull,
                    );

                    if (filtered.isEmpty) {
                      return ListView(
                        children: [
                          const SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.search_off_rounded,
                            title: shifts.isEmpty
                                ? 'No open shifts right now'
                                : 'No matches',
                            subtitle: shifts.isEmpty
                                ? 'Pull to refresh — new shifts appear here live.'
                                : 'Try adjusting your search or filters.',
                          ),
                        ],
                      );
                    }

                    return ListView.separated(
                      padding: const EdgeInsets.all(AppSpacing.md),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final shift = filtered[i];
                        return _NearMeAwareCard(
                          shift: shift,
                          nearMeOnly: _nearMeOnly,
                          ownArea: ownAreaAsync.valueOrNull,
                          index: i,
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Filter Panel ─────────────────────────────────────────────────────────────

class _FilterPanel extends StatelessWidget {
  const _FilterPanel({
    required this.nearMeOnly,
    required this.ownAreaAsync,
    required this.dateFilter,
    required this.pickedDate,
    required this.minPayRate,
    required this.sortOrder,
    required this.hasActiveFilters,
    required this.onNearMeToggle,
    required this.onDateFilter,
    required this.onPayRateChange,
    required this.onSortChange,
    required this.onClear,
  });

  final bool nearMeOnly;
  final AsyncValue<String?> ownAreaAsync;
  final _DateFilter dateFilter;
  final DateTime? pickedDate;
  final double minPayRate;
  final _SortOrder sortOrder;
  final bool hasActiveFilters;
  final ValueChanged<bool>? onNearMeToggle;
  final ValueChanged<_DateFilter> onDateFilter;
  final ValueChanged<double> onPayRateChange;
  final ValueChanged<_SortOrder> onSortChange;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('d MMM');
    final noLocation = ownAreaAsync.valueOrNull == null;

    return Container(
      margin: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section label row
            Row(
              children: [
                Expanded(
                  child: Text(
                    'FILTERS & SORT',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      letterSpacing: 1.1,
                    ),
                  ),
                ),
                if (hasActiveFilters)
                  TextButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear_all_rounded, size: 16),
                    label: const Text('Clear all'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      visualDensity: VisualDensity.compact,
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Near me ────────────────────────────────────────────────────
            _FilterSectionLabel('📍 Location'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: Text(
                    noLocation ? 'Near me (set location)' : 'Near me',
                  ),
                  avatar: noLocation
                      ? Icon(
                          Icons.location_off_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        )
                      : Icon(
                          Icons.near_me_rounded,
                          size: 14,
                          color: nearMeOnly
                              ? scheme.onPrimary
                              : scheme.onSurface,
                        ),
                  selected: nearMeOnly,
                  onSelected: onNearMeToggle,
                ),
                if (ownAreaAsync.valueOrNull != null)
                  Chip(
                    avatar: Icon(
                      Icons.place_rounded,
                      size: 14,
                      color: scheme.primary,
                    ),
                    label: Text(
                      ownAreaAsync.valueOrNull!,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),

            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),

            // ── Date ───────────────────────────────────────────────────────
            _FilterSectionLabel('📅 Date'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _DateFilter.values.map((f) {
                final label =
                    f == _DateFilter.pickDate &&
                        dateFilter == _DateFilter.pickDate &&
                        pickedDate != null
                    ? dateFmt.format(pickedDate!)
                    : f.label;
                return FilterChip(
                  label: Text(label),
                  selected: dateFilter == f,
                  onSelected: (_) => onDateFilter(f),
                );
              }).toList(),
            ),

            const SizedBox(height: AppSpacing.sm),
            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),

            // ── Minimum pay rate ────────────────────────────────────────────
            Row(
              children: [
                _FilterSectionLabel('💷 Min pay rate'),
                const Spacer(),
                Text(
                  minPayRate == 0
                      ? 'Any'
                      : '£${minPayRate.toStringAsFixed(0)}/hr+',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: minPayRate > 0
                        ? AppColors.coral
                        : scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Slider(
              value: minPayRate,
              min: 0,
              max: 30,
              divisions: 30,
              label: minPayRate == 0
                  ? 'Any'
                  : '£${minPayRate.toStringAsFixed(0)}/hr',
              onChanged: onPayRateChange,
            ),

            const Divider(height: 1),
            const SizedBox(height: AppSpacing.sm),

            // ── Sort ───────────────────────────────────────────────────────
            _FilterSectionLabel('↕️ Sort by'),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: _SortOrder.values.map((s) {
                return FilterChip(
                  avatar: Icon(s.icon, size: 14),
                  label: Text(s.label),
                  selected: sortOrder == s,
                  onSelected: (_) => onSortChange(s),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Category tile ────────────────────────────────────────────────────────────


class _FilterSectionLabel extends StatelessWidget {
  const _FilterSectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
  );
}

// ─── Active filter chips (collapsed view) ────────────────────────────────────

class _ActiveFilterChips extends StatelessWidget {
  const _ActiveFilterChips({
    required this.nearMeOnly,
    required this.dateFilter,
    required this.pickedDate,
    required this.minPayRate,
    required this.sortOrder,
    required this.onClear,
  });

  final bool nearMeOnly;
  final _DateFilter dateFilter;
  final DateTime? pickedDate;
  final double minPayRate;
  final _SortOrder sortOrder;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final dateFmt = DateFormat('d MMM');
    final chips = <String>[];

    if (nearMeOnly) chips.add('📍 Near me');
    if (dateFilter == _DateFilter.pickDate && pickedDate != null) {
      chips.add('📅 ${dateFmt.format(pickedDate!)}');
    } else if (dateFilter != _DateFilter.any) {
      chips.add('📅 ${dateFilter.label}');
    }
    if (minPayRate > 0) chips.add('💷 £${minPayRate.toStringAsFixed(0)}+/hr');
    if (sortOrder != _SortOrder.soonest) chips.add('↕ ${sortOrder.label}');

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 8, AppSpacing.md, 0),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: chips
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Chip(
                          label: Text(c, style: const TextStyle(fontSize: 11)),
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 0,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18),
            onPressed: onClear,
            tooltip: 'Clear filters',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ],
      ),
    );
  }
}

// ─── Near-me aware card wrapper ───────────────────────────────────────────────

/// Wraps ShiftCard so the "Near me" filter can hide a card once its
/// nursery's area is known (fetched lazily per-card, cached per-uid) —
/// avoids blocking the whole list on every nursery lookup finishing first.
class _NearMeAwareCard extends ConsumerWidget {
  const _NearMeAwareCard({
    required this.shift,
    required this.nearMeOnly,
    required this.ownArea,
    required this.index,
  });

  final Shift shift;
  final bool nearMeOnly;
  final String? ownArea;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // B1 fix: Near me filtering is evaluated in _applyFilters, eliminating
    // SizedBox.shrink() separator gaps and empty-state bugs.
    return _card(context, null);
  }

  Widget _card(BuildContext context, String? area) {
    return ShiftCard(
          shift: shift,
          trailingLabel: 'Book Shift',
          onTap: () => context.push('/shifts/${shift.id}'),
        )
        .animate()
        .fadeIn(delay: (40 * index).ms, duration: 300.ms)
        .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
  }
}

// ─── Stitch Alexandria Utility Header Action Button ──────────────────────────

class _CircularHeaderAction extends StatelessWidget {
  const _CircularHeaderAction({
    required this.icon,
    required this.onTap,
    this.isActive = false,
    this.badgeColor,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool isActive;
  final Color? badgeColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              border: Border.all(
                color: isActive ? const Color(0xFF1B2A4A) : const Color(0xFFE2E8F0),
                width: isActive ? 1.2 : 1.0,
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x080F172A), blurRadius: 4, offset: Offset(0, 1)),
              ],
            ),
            child: Icon(
              icon,
              size: 18,
              color: isActive ? const Color(0xFF1B2A4A) : const Color(0xFF475569),
            ),
          ),
          if (badgeColor != null && isActive)
            Positioned(
              top: 1,
              right: 1,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─── Stitch Alexandria Quick Filter Pill ──────────────────────────────────────

class _QuickPill extends StatelessWidget {
  const _QuickPill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.count,
    this.dotColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final int? count;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF1B2A4A) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? const Color(0xFF1B2A4A) : const Color(0xFFE2E8F0),
          ),
          boxShadow: [
            if (!selected)
              const BoxShadow(color: Color(0x060F172A), blurRadius: 4, offset: Offset(0, 1)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                color: selected ? Colors.white : const Color(0xFF334155),
              ),
            ),
            if (count != null) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                decoration: BoxDecoration(
                  color: selected ? Colors.white.withValues(alpha: 0.22) : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: selected ? Colors.white : const Color(0xFF64748B),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Stitch Alexandria Date Horizon Selector ──────────────────────────────────

class _DateHorizonSelector extends StatelessWidget {
  const _DateHorizonSelector({
    required this.activeFilter,
    required this.pickedDate,
    required this.onSelect,
  });

  final _DateFilter activeFilter;
  final DateTime? pickedDate;
  final void Function(_DateFilter filter, DateTime? date) onSelect;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final days = List.generate(5, (i) {
      final d = today.add(Duration(days: i));
      final isToday = i == 0;
      final dayName = isToday ? 'TODAY' : DateFormat('EEE').format(d).toUpperCase();
      final dateNum = DateFormat('d MMM').format(d);
      final isSelected = (activeFilter == _DateFilter.today && isToday) ||
          (activeFilter == _DateFilter.pickDate &&
              pickedDate != null &&
              pickedDate!.year == d.year &&
              pickedDate!.month == d.month &&
              pickedDate!.day == d.day);

      return (d, isToday, dayName, dateNum, isSelected);
    });

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: days.map((item) {
          final (d, isToday, dayName, dateNum, isSelected) = item;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                if (isToday) {
                  onSelect(activeFilter == _DateFilter.today ? _DateFilter.any : _DateFilter.today, null);
                } else {
                  onSelect(_DateFilter.pickDate, d);
                }
              },
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF1B2A4A) : Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isSelected ? const Color(0xFF1B2A4A) : const Color(0xFFE2E8F0),
                  ),
                  boxShadow: const [
                    BoxShadow(color: Color(0x060F172A), blurRadius: 4, offset: Offset(0, 1)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dayName,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: isSelected ? const Color(0xFFCBD5E1) : const Color(0xFF94A3B8),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      dateNum,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: isSelected ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

