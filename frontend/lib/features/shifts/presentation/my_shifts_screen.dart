import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../../shared/widgets/shimmer_box.dart';
import '../../profile/domain/profile.dart';
import '../domain/shift.dart';
import 'widgets/shift_card.dart';

final myShiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  final profile = ref.watch(ownProfileProvider).valueOrNull;
  if (user == null || profile == null) return Future.value(<Shift>[]);
  return ref.watch(shiftRepositoryProvider).fetchMyShifts();
});

enum _ShiftTab { active, completed, cancelled }

class MyShiftsScreen extends ConsumerStatefulWidget {
  const MyShiftsScreen({super.key});

  @override
  ConsumerState<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends ConsumerState<MyShiftsScreen> {
  _ShiftTab _selectedTab = _ShiftTab.active;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final isNursery = profile?.role == UserRole.nursery;
    final shiftsAsync = ref.watch(myShiftsProvider);
    final now = DateTime.now();
    final firstName = profile?.name.trim().split(' ').firstOrNull ?? '';

    return Scaffold(
      body: Column(
        children: [
          // ── Gradient hero: avatar + greeting + bell ──────────────────
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
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.white.withValues(alpha: 0.18),
                  backgroundImage: (profile?.photoUrl.isNotEmpty ?? false)
                      ? NetworkImage(profile!.photoUrl)
                      : null,
                  child: (profile == null || profile.photoUrl.isEmpty)
                      ? Icon(
                          isNursery
                              ? Icons.home_work_outlined
                              : Icons.person_outline_rounded,
                          color: Colors.white,
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Welcome back 👋',
                        style: TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      Text(
                        firstName.isNotEmpty
                            ? firstName
                            : (isNursery
                                  ? 'Your posted shifts'
                                  : 'Your booked shifts'),
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
                const NotificationIconButton(color: Colors.white70),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Sleek compact tab selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Container(
              height: 40,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Row(
                children: [
                  _ShiftTabTile(
                    label: 'Active',
                    selected: _selectedTab == _ShiftTab.active,
                    onTap: () => setState(() => _selectedTab = _ShiftTab.active),
                  ),
                  _ShiftTabTile(
                    label: 'Completed',
                    selected: _selectedTab == _ShiftTab.completed,
                    onTap: () => setState(() => _selectedTab = _ShiftTab.completed),
                  ),
                  _ShiftTabTile(
                    label: 'Cancelled',
                    selected: _selectedTab == _ShiftTab.cancelled,
                    onTap: () => setState(() => _selectedTab = _ShiftTab.cancelled),
                  ),
                ],
              ),
            ),
          ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async => ref.invalidate(myShiftsProvider),
                child: shiftsAsync.when(
                  loading: () => ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: 3,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (_, __) => const ShiftCardSkeleton(),
                  ),
                  error: (e, _) => EmptyState(
                    icon: Icons.wifi_off_rounded,
                    title: "Couldn't load your shifts",
                    subtitle: '$e',
                  ),
                  data: (allShifts) {
                    final filtered = allShifts.where((s) {
                      final isDone = now.isAfter(s.endTime);
                      return switch (_selectedTab) {
                        _ShiftTab.active =>
                          s.status != ShiftStatus.cancelled && !isDone,
                        _ShiftTab.completed =>
                          s.status != ShiftStatus.cancelled && isDone,
                        _ShiftTab.cancelled =>
                          s.status == ShiftStatus.cancelled,
                      };
                    }).toList();

                    if (filtered.isEmpty) {
                      final emptyTitle = switch (_selectedTab) {
                        _ShiftTab.active => 'No active shifts',
                        _ShiftTab.completed => 'No completed shifts yet',
                        _ShiftTab.cancelled => 'No cancelled shifts',
                      };
                      return ListView(
                        children: [
                          const SizedBox(height: 60),
                          EmptyState(
                            icon: isNursery
                                ? Icons.post_add_rounded
                                : Icons.event_note_outlined,
                            title: emptyTitle,
                            subtitle: 'Pull to refresh to update status.',
                          ),
                        ],
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        AppSpacing.md,
                        AppSpacing.md,
                        88,
                      ),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) {
                        final shift = filtered[i];
                        return ShiftCard(
                              shift: shift,
                              onTap: () => context.push('/shifts/${shift.id}'),
                            )
                            .animate()
                            .fadeIn(delay: (40 * i).ms, duration: 300.ms)
                            .slideY(begin: 0.05, end: 0);
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

class _ShiftTabTile extends StatelessWidget {
  const _ShiftTabTile({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.06),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              color: selected ? AppColors.indigo : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}
