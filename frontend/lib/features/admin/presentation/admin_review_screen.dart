import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../../documents/domain/document_status.dart';
import '../../profile/domain/profile.dart';
import '../domain/admin_models.dart';

final pendingDocumentsProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(documentsRepositoryProvider).listPendingDocuments();
});

final platformStatsProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(adminRepositoryProvider).getPlatformStats();
});

final allUsersProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(adminRepositoryProvider).listAllUsers();
});

/// The Bridge Flex super-admin's home screen — full app spec admin-page
/// request: a platform-metrics dashboard, the documents review queue, and
/// user management (view profile/documents, suspend, verification badges).
/// Reached only via router.dart's isAdminProvider short-circuit, never
/// through role-select/onboarding.
class AdminReviewScreen extends ConsumerWidget {
  const AdminReviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Overview'),
              Tab(text: 'Queue'),
              Tab(text: 'Users'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.logout_rounded),
              tooltip: 'Sign out',
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
            ),
          ],
        ),
        body: const TabBarView(
          children: [_OverviewTab(), _QueueTab(), _UsersTab()],
        ),
      ),
    );
  }
}

// ─── Overview ─────────────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(platformStatsProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(platformStatsProvider),
      child: statsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: 80),
            EmptyState(icon: Icons.error_outline, title: "Couldn't load stats", subtitle: '$e'),
          ],
        ),
        data: (stats) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text('Platform', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            _StatGrid(items: [
              _Stat('Nurseries', '${stats.totalNurseries}', Icons.home_work_rounded, AppColors.indigo),
              _Stat('Staff', '${stats.totalStaff}', Icons.badge_rounded, AppColors.indigo),
              _Stat('Suspended', '${stats.suspendedUsers}', Icons.block_rounded, Theme.of(context).colorScheme.error),
              _Stat('Pending DBS', '${stats.pendingDbs}', Icons.pending_actions_rounded, AppColors.amber),
            ]),
            const SizedBox(height: AppSpacing.lg),
            Text('Shifts', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: AppSpacing.sm),
            _StatGrid(items: [
              _Stat('Total', '${stats.totalShifts}', Icons.event_note_rounded, AppColors.indigo),
              _Stat('Open', '${stats.openShifts}', Icons.event_available_rounded, AppColors.mint),
              _Stat('Booked', '${stats.bookedShifts}', Icons.event_busy_rounded, AppColors.amber),
              _Stat('Completed', '${stats.completedShifts}', Icons.check_circle_rounded, AppColors.mint),
              _Stat('Cancelled', '${stats.cancelledShifts}', Icons.cancel_rounded, Theme.of(context).colorScheme.error),
              _Stat('Ratings given', '${stats.totalRatings}', Icons.star_rounded, AppColors.amber),
            ]),
            const SizedBox(height: AppSpacing.lg),
            _StatGrid(items: [
              _Stat('Docs awaiting review', '${stats.pendingDocuments}', Icons.folder_shared_rounded, AppColors.coral),
            ]),
          ],
        ).animate().fadeIn(duration: 250.ms),
      ),
    );
  }
}

class _Stat {
  const _Stat(this.label, this.value, this.icon, this.color);
  final String label;
  final String value;
  final IconData icon;
  final Color color;
}

class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.items});
  final List<_Stat> items;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.sm,
        crossAxisSpacing: AppSpacing.sm,
        // A fixed extent (rather than aspect ratio) guarantees enough
        // height for icon + two text lines + card padding regardless of
        // device width — aspect ratio 2.4 measured ~11px short on narrower
        // phones.
        mainAxisExtent: 80,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Icon(item.icon, color: item.color, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(item.value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
                      Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ─── Queue ────────────────────────────────────────────────────────────────────

class _QueueTab extends ConsumerWidget {
  const _QueueTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingDocumentsProvider);
    final usersAsync = ref.watch(allUsersProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(pendingDocumentsProvider);
        ref.invalidate(allUsersProvider);
      },
      child: pendingAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const SizedBox(height: 80),
            EmptyState(icon: Icons.error_outline, title: "Couldn't load queue", subtitle: '$e'),
          ],
        ),
        data: (docs) {
          if (docs.isEmpty) {
            return ListView(
              padding: const EdgeInsets.all(AppSpacing.lg),
              children: const [
                SizedBox(height: 80),
                EmptyState(
                  icon: Icons.task_alt_rounded,
                  title: 'All caught up',
                  subtitle: 'No documents are waiting for review.',
                ),
              ],
            );
          }
          // Group pending documents by uploader — the queue is a list of
          // people to review, not a flat list of files; approve/reject
          // happens per-document on their detail page (full app spec: "when
          // i click the user i should see all documents ... and verify, one
          // by one").
          final byUid = <String, List<PendingDocument>>{};
          for (final d in docs) {
            byUid.putIfAbsent(d.uid, () => []).add(d);
          }
          final users = usersAsync.valueOrNull ?? const [];
          final entries = byUid.entries.toList();

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, i) {
              final uid = entries[i].key;
              final pending = entries[i].value;
              final user = users.where((u) => u.uid == uid).firstOrNull;
              return _QueueUserCard(uid: uid, user: user, pendingCount: pending.length)
                  .animate()
                  .fadeIn(delay: (i * 30).ms, duration: 200.ms);
            },
          );
        },
      ),
    );
  }
}

class _QueueUserCard extends StatelessWidget {
  const _QueueUserCard({required this.uid, required this.user, required this.pendingCount});

  final String uid;
  final AdminUserSummary? user;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNursery = user?.role == UserRole.nursery;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.push('/admin/users/$uid'),
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(
            isNursery ? Icons.home_work_outlined : Icons.badge_outlined,
            color: scheme.primary,
            size: 20,
          ),
        ),
        title: Text(
          (user?.name.isNotEmpty ?? false) ? user!.name : uid,
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          '${user == null ? 'Unknown role' : (isNursery ? 'Nursery' : 'Staff')} · $pendingCount document${pendingCount == 1 ? '' : 's'} pending',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}

// ─── Users ────────────────────────────────────────────────────────────────────

enum _UserFilter { all, nurseries, staff, suspended, pendingDbs }

extension on _UserFilter {
  String get label => switch (this) {
        _UserFilter.all => 'All',
        _UserFilter.nurseries => 'Nurseries',
        _UserFilter.staff => 'Staff',
        _UserFilter.suspended => 'Suspended',
        _UserFilter.pendingDbs => 'Pending DBS',
      };
}

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  final _searchController = TextEditingController();
  String _query = '';
  _UserFilter _filter = _UserFilter.all;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AdminUserSummary> _apply(List<AdminUserSummary> users) {
    var filtered = users.where((u) {
      switch (_filter) {
        case _UserFilter.all:
          return true;
        case _UserFilter.nurseries:
          return u.role == UserRole.nursery;
        case _UserFilter.staff:
          return u.role == UserRole.staff;
        case _UserFilter.suspended:
          return u.suspended;
        case _UserFilter.pendingDbs:
          return u.dbsStatus == DbsStatus.pending;
      }
    }).toList();
    if (_query.isNotEmpty) {
      filtered = filtered
          .where((u) =>
              u.name.toLowerCase().contains(_query) ||
              u.email.toLowerCase().contains(_query) ||
              u.phone.contains(_query))
          .toList();
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(allUsersProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search by name, email or phone…',
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
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 4,
            children: _UserFilter.values.map((f) {
              return FilterChip(
                label: Text(f.label),
                selected: _filter == f,
                onSelected: (_) => setState(() => _filter = f),
              );
            }).toList(),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => ref.invalidate(allUsersProvider),
            child: usersAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  const SizedBox(height: 80),
                  EmptyState(icon: Icons.error_outline, title: "Couldn't load users", subtitle: '$e'),
                ],
              ),
              data: (users) {
                final filtered = _apply(users);
                if (filtered.isEmpty) {
                  return ListView(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    children: const [
                      SizedBox(height: 80),
                      EmptyState(icon: Icons.people_outline_rounded, title: 'No matching users', subtitle: 'Try a different search or filter.'),
                    ],
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (context, i) => _UserRow(user: filtered[i]),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({required this.user});
  final AdminUserSummary user;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _busy = false;

  Future<void> _toggleSuspend() async {
    final suspending = !widget.user.suspended;
    if (suspending) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Suspend this account?'),
          content: Text(
            '${widget.user.name.isEmpty ? 'This user' : widget.user.name} will be signed out and unable to sign back in until reinstated.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('Suspend'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(adminRepositoryProvider).setUserSuspended(
            uid: widget.user.uid,
            suspended: suspending,
          );
      ref.invalidate(allUsersProvider);
      ref.invalidate(platformStatsProvider);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = widget.user;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.push('/admin/users/${user.uid}'),
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Icon(
            user.role == UserRole.nursery ? Icons.home_work_outlined : Icons.badge_outlined,
            color: scheme.primary,
            size: 20,
          ),
        ),
        title: Text(user.name.isEmpty ? '(no name yet)' : user.name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Row(
          children: [
            Text(user.role == UserRole.nursery ? 'Nursery' : 'Staff', style: TextStyle(color: scheme.onSurfaceVariant)),
            if (user.suspended) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: scheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text('Suspended', style: TextStyle(fontSize: 11, color: scheme.error, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
        trailing: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : IconButton(
                icon: Icon(
                  user.suspended ? Icons.lock_open_rounded : Icons.block_rounded,
                  color: user.suspended ? AppColors.mint : scheme.error,
                ),
                tooltip: user.suspended ? 'Reinstate' : 'Suspend',
                onPressed: _toggleSuspend,
              ),
      ),
    );
  }
}
