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
    final scheme = Theme.of(context).colorScheme;
    final firstName = profile?.name.trim().split(' ').firstOrNull ?? '';

    return Scaffold(
      floatingActionButton: isNursery
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/shifts/new'),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Post shift'),
            ).animate().scale(
              delay: 200.ms,
              duration: 300.ms,
              curve: Curves.easeOutBack,
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            // ── Hero header: avatar + greeting + bell ────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: scheme.primary.withValues(alpha: 0.12),
                    backgroundImage: (profile?.photoUrl.isNotEmpty ?? false)
                        ? NetworkImage(profile!.photoUrl)
                        : null,
                    child: (profile == null || profile.photoUrl.isEmpty)
                        ? Icon(
                            isNursery
                                ? Icons.home_work_outlined
                                : Icons.person_outline_rounded,
                            color: scheme.primary,
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back 👋',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        Text(
                          firstName.isNotEmpty
                              ? firstName
                              : (isNursery
                                    ? 'Your posted shifts'
                                    : 'Your booked shifts'),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const NotificationIconButton(),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              child: SegmentedButton<_ShiftTab>(
                segments: const [
                  ButtonSegment(
                    value: _ShiftTab.active,
                    label: Text('Active'),
                    icon: Icon(Icons.flash_on_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: _ShiftTab.completed,
                    label: Text('Completed'),
                    icon: Icon(Icons.check_circle_outline_rounded, size: 16),
                  ),
                  ButtonSegment(
                    value: _ShiftTab.cancelled,
                    label: Text('Cancelled'),
                    icon: Icon(Icons.cancel_outlined, size: 16),
                  ),
                ],
                selected: {_selectedTab},
                onSelectionChanged: (set) =>
                    setState(() => _selectedTab = set.first),
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
      ),
    );
  }
}
