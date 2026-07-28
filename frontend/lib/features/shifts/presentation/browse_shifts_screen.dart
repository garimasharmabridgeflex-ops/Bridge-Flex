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

/// One `fetchPublicProfile` per unique nurseryId, cached per-uid by Riverpod
/// — a shift list of N shifts across M unique nurseries makes M calls, not
/// N. Backs the "Near me" filter (locationArea is the coarse geohash prefix
/// already used everywhere else, ARCHITECTURE.md v2 §2 — a real distance/
/// radius search is an open product question, §8 item 4; matching on that
/// same prefix is a reasonable "same broad area" proxy without deciding it).
final _nurseryLocationAreaProvider = FutureProvider.autoDispose
    .family<String?, String>((ref, nurseryId) async {
      final profile = await ref
          .watch(profileRepositoryProvider)
          .fetchPublicProfile(nurseryId);
      return profile?.locationArea;
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
  bool _nearMeOnly = false;
  _DateFilter _dateFilter = _DateFilter.any;
  DateTime? _pickedDate;
  double _minPayRate = 0;
  _SortOrder _sortOrder = _SortOrder.soonest;
  bool _showFilters = false;
  String? _categoryFilter;

  static const _categoryOptions = [
    ('Babies (0-2)', Icons.child_care_rounded),
    ('Toddlers (2-3)', Icons.emoji_people_rounded),
    ('Preschool (3-5)', Icons.school_rounded),
    ('Mixed ages', Icons.groups_rounded),
  ];

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning 👋';
    if (hour < 17) return 'Good afternoon 👋';
    return 'Good evening 👋';
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
      body: Column(
        children: [
          // ── Gradient hero: greeting + bell + search ──────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
            ),
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.indigo, AppColors.indigoDeep],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(AppRadius.lg),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      radius: 20,
                      backgroundColor: Colors.white.withValues(alpha: 0.18),
                      backgroundImage: (profile?.photoUrl.isNotEmpty ?? false)
                          ? NetworkImage(profile!.photoUrl)
                          : null,
                      child: (profile == null || profile.photoUrl.isEmpty)
                          ? const Icon(
                              Icons.person_outline_rounded,
                              color: Colors.white,
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _greeting(),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                          Text(
                            firstName.isNotEmpty ? firstName : 'Open shifts',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 18,
                              color: Colors.white,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    Stack(
                      children: [
                        IconButton(
                          icon: Icon(
                            Icons.tune_rounded,
                            color: _hasActiveFilters
                                ? Colors.white
                                : Colors.white70,
                          ),
                          tooltip: 'Filters & Sort',
                          onPressed: () =>
                              setState(() => _showFilters = !_showFilters),
                        ),
                        if (_hasActiveFilters)
                          Positioned(
                            right: 8,
                            top: 8,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: AppColors.coral,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const NotificationIconButton(color: Colors.white70),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _searchController,
                  onChanged: (v) =>
                      setState(() => _query = v.trim().toLowerCase()),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: Colors.white,
                    hintText: 'Search shifts by title…',
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () => setState(() {
                              _searchController.clear();
                              _query = '';
                            }),
                          ),
                  ),
                ),
              ],
            ),
          ),

          // ── Category quick filters ────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Category',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
            SizedBox(
              height: 84,
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                scrollDirection: Axis.horizontal,
                itemCount: _categoryOptions.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final (label, icon) = _categoryOptions[i];
                  final selected = _categoryFilter == label;
                  return _CategoryTile(
                    label: label,
                    icon: icon,
                    selected: selected,
                    onTap: () => setState(
                      () => _categoryFilter = selected ? null : label,
                    ),
                  );
                },
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
                        onNearMeToggle: ownAreaAsync.valueOrNull == null
                            ? null
                            : (v) => setState(() => _nearMeOnly = v),
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

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shortLabel = label.split(' ').first;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 56,
              width: 56,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.indigo
                    : AppColors.indigo.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: AppColors.indigo.withValues(alpha: 0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 4),
                        ),
                      ]
                    : null,
                border: Border.all(
                  color: selected
                      ? AppColors.indigo
                      : AppColors.indigo.withValues(alpha: 0.15),
                ),
              ),
              child: Icon(
                icon,
                color: selected ? Colors.white : AppColors.indigo,
                size: 26,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              shortLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.indigo : scheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    if (!nearMeOnly || ownArea == null) {
      return _card(context, null);
    }
    final areaAsync = ref.watch(_nurseryLocationAreaProvider(shift.nurseryId));
    return areaAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (area) =>
          area == ownArea ? _card(context, area) : const SizedBox.shrink(),
    );
  }

  Widget _card(BuildContext context, String? area) {
    return ShiftCard(
          shift: shift,
          trailingLabel: 'View →',
          onTap: () => context.push('/shifts/${shift.id}'),
        )
        .animate()
        .fadeIn(delay: (40 * index).ms, duration: 300.ms)
        .slideY(begin: 0.05, end: 0, curve: Curves.easeOutCubic);
  }
}
