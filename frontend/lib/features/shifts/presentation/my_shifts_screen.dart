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
import '../data/bookmarks_provider.dart';
import '../domain/shift.dart';
import 'widgets/shift_card.dart';

final myShiftsProvider = FutureProvider.autoDispose<List<Shift>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  final profile = ref.watch(ownProfileProvider).valueOrNull;
  if (user == null || profile == null) return Future.value(<Shift>[]);
  return ref.watch(shiftRepositoryProvider).fetchMyShifts();
});

enum _ShiftTab { upcoming, completed, cancelled, saved }

class MyShiftsScreen extends ConsumerStatefulWidget {
  const MyShiftsScreen({super.key});

  @override
  ConsumerState<MyShiftsScreen> createState() => _MyShiftsScreenState();
}

class _MyShiftsScreenState extends ConsumerState<MyShiftsScreen> {
  _ShiftTab _selectedTab = _ShiftTab.upcoming;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final isNursery = profile?.role == UserRole.nursery;
    final shiftsAsync = ref.watch(myShiftsProvider);
    final savedShiftsAsync = ref.watch(savedShiftsListProvider);
    final now = DateTime.now();
    final firstName = profile?.name.trim().split(' ').firstOrNull ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Clean Editorial Top Header ─────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0), width: 0.8)),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: const Color(0xFFE2E8F0),
                    backgroundImage: (profile?.photoUrl.isNotEmpty ?? false)
                        ? NetworkImage(profile!.photoUrl)
                        : null,
                    child: (profile == null || profile.photoUrl.isEmpty)
                        ? Icon(
                            isNursery
                                ? Icons.home_work_outlined
                                : Icons.person_rounded,
                            color: const Color(0xFF1B2A4A),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isNursery ? 'NURSERY DASHBOARD' : 'MY SCHEDULE & BOOKINGS',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF64748B),
                            letterSpacing: 0.6,
                          ),
                        ),
                        Text(
                          isNursery
                              ? 'Posted Shifts'
                              : (firstName.isNotEmpty ? '$firstName’s Shifts' : 'My Shifts'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 17,
                            color: Color(0xFF0F172A),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const NotificationIconButton(color: Color(0xFF1B2A4A)),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // ── Modern Tab Selector ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                height: 42,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0).withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Row(
                  children: [
                    _ShiftTabTile(
                      label: isNursery ? 'Active' : 'Upcoming',
                      selected: _selectedTab == _ShiftTab.upcoming,
                      onTap: () => setState(() => _selectedTab = _ShiftTab.upcoming),
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
                    _ShiftTabTile(
                      label: 'Saved',
                      icon: Icons.bookmark_rounded,
                      selected: _selectedTab == _ShiftTab.saved,
                      onTap: () => setState(() => _selectedTab = _ShiftTab.saved),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),

            // ── Content Area ───────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF1B2A4A),
                onRefresh: () async {
                  ref.invalidate(myShiftsProvider);
                  ref.invalidate(savedShiftsListProvider);
                },
                child: _selectedTab == _ShiftTab.saved
                    ? savedShiftsAsync.when(
                        loading: () => ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: 2,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
                          itemBuilder: (_, __) => const ShiftCardSkeleton(),
                        ),
                        error: (e, _) => EmptyState(
                          icon: Icons.wifi_off_rounded,
                          title: "Couldn't load saved shifts",
                          subtitle: '$e',
                        ),
                        data: (savedShifts) {
                          if (savedShifts.isEmpty) {
                            return ListView(
                              children: const [
                                SizedBox(height: 60),
                                EmptyState(
                                  icon: Icons.bookmark_border_rounded,
                                  title: 'No saved shifts',
                                  subtitle:
                                      'Tap the bookmark icon on any shift in Browse to save it here for quick access.',
                                ),
                              ],
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: savedShifts.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final shift = savedShifts[i];
                              return ShiftCard(
                                shift: shift,
                                onTap: () => context.push('/shifts/${shift.id}'),
                              ).animate().fadeIn(duration: 200.ms);
                            },
                          );
                        },
                      )
                    : shiftsAsync.when(
                        loading: () => ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: 3,
                          separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                              _ShiftTab.upcoming =>
                                s.status != ShiftStatus.cancelled && !isDone,
                              _ShiftTab.completed =>
                                s.status != ShiftStatus.cancelled && isDone,
                              _ShiftTab.cancelled =>
                                s.status == ShiftStatus.cancelled,
                              _ShiftTab.saved => true,
                            };
                          }).toList();

                          if (filtered.isEmpty) {
                            final emptyTitle = switch (_selectedTab) {
                              _ShiftTab.upcoming => isNursery
                                  ? 'No active shifts posted'
                                  : 'No upcoming shifts booked',
                              _ShiftTab.completed => 'No completed shifts yet',
                              _ShiftTab.cancelled => 'No cancelled shifts',
                              _ShiftTab.saved => 'No saved shifts',
                            };
                            return ListView(
                              children: [
                                const SizedBox(height: 60),
                                EmptyState(
                                  icon: isNursery
                                      ? Icons.post_add_rounded
                                      : Icons.event_note_outlined,
                                  title: emptyTitle,
                                  subtitle: isNursery
                                      ? 'Post early years shifts to find verified practitioners.'
                                      : 'Browse available shifts to find nursery work.',
                                ),
                                if (isNursery) ...[
                                  const SizedBox(height: 16),
                                  Center(
                                    child: FilledButton.icon(
                                      onPressed: () => context.push('/shifts/new'),
                                      icon: const Icon(Icons.add_rounded),
                                      label: const Text('Post Shift Now'),
                                      style: FilledButton.styleFrom(
                                        backgroundColor: const Color(0xFF1B2A4A),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            );
                          }
                          return ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, i) {
                              final shift = filtered[i];
                              final user = ref.watch(authStateProvider).valueOrNull;
                              final isPending =
                                  user != null && shift.hasAppliedBy(user.uid);
                              return ShiftCard(
                                shift: shift,
                                isPendingApproval: isPending,
                                onTap: () => context.push('/shifts/${shift.id}'),
                              )
                                  .animate()
                                  .fadeIn(delay: (30 * i).ms, duration: 250.ms);
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

class _ShiftTabTile extends StatelessWidget {
  const _ShiftTabTile({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x100F172A),
                      blurRadius: 4,
                      offset: Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(
                  icon,
                  size: 13,
                  color: selected ? const Color(0xFF1B2A4A) : const Color(0xFF64748B),
                ),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected ? const Color(0xFF1B2A4A) : const Color(0xFF64748B),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
