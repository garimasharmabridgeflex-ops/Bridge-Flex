import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/notification_item.dart';

final notificationsListProvider = FutureProvider.autoDispose((ref) {
  return ref.watch(notificationsRepositoryProvider).list();
});

final unreadNotificationCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final items = await ref.watch(notificationsRepositoryProvider).list();
  return items.where((n) => !n.read).length;
});

class NotificationIconButton extends ConsumerWidget {
  const NotificationIconButton({super.key, this.color});

  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadAsync = ref.watch(unreadNotificationCountProvider);
    final count = unreadAsync.valueOrNull ?? 0;

    return IconButton(
      tooltip: 'Notifications',
      onPressed: () => context.push('/notifications'),
      icon: count > 0
          ? Badge(
              label: Text('$count'),
              child: Icon(Icons.notifications_outlined, color: color),
            )
          : Icon(Icons.notifications_outlined, color: color),
    );
  }
}

class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          IconButton(
            icon: const Icon(Icons.done_all_rounded),
            tooltip: 'Mark all as read',
            onPressed: () async {
              try {
                await ref.read(notificationsRepositoryProvider).markAllRead();
                ref.invalidate(notificationsListProvider);
                ref.invalidate(unreadNotificationCountProvider);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('All notifications marked as read')),
                  );
                }
              } catch (_) {}
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(notificationsListProvider),
        child: notificationsAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 80),
            EmptyState(
                icon: Icons.error_outline,
                title: "Couldn't load notifications",
                subtitle: '$e'),
          ]),
          data: (items) {
            if (items.isEmpty) {
              return ListView(
                children: const [
                  SizedBox(height: 80),
                  EmptyState(
                    icon: Icons.notifications_none_rounded,
                    title: 'All caught up',
                    subtitle:
                        'Booking confirmations, new shifts, and rating alerts will appear here.',
                  ),
                ],
              );
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (context, i) {
                final n = items[i];
                return _NotificationTile(item: n)
                    .animate()
                    .fadeIn(delay: (30 * i).ms, duration: 250.ms)
                    .slideX(begin: 0.03, end: 0);
              },
            );
          },
        ),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});

  final NotificationItem item;

  IconData get _icon => switch (item.type) {
        'shift_booked' => Icons.event_available_rounded,
        'new_matching_shift' => Icons.campaign_outlined,
        'rating_received' => Icons.star_outline_rounded,
        'shift_cancelled' => Icons.event_busy_rounded,
        'shift_uncovered' => Icons.warning_amber_rounded,
        _ => Icons.notifications_outlined,
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final shiftId = item.payload['shiftId'] as String?;

    return InkWell(
      onTap: () async {
        if (!item.read) {
          try {
            await ref.read(notificationsRepositoryProvider).markRead(item.id);
            ref.invalidate(notificationsListProvider);
            ref.invalidate(unreadNotificationCountProvider);
          } catch (_) {}
        }
        if (shiftId != null && context.mounted) {
          context.push('/shifts/$shiftId');
        }
      },
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: item.read
              ? scheme.surface
              : scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: item.read
                ? scheme.outlineVariant.withValues(alpha: 0.3)
                : scheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: item.read
                    ? scheme.surfaceContainerHighest
                    : scheme.primary.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon,
                size: 20,
                color: item.read ? scheme.onSurfaceVariant : scheme.primary,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: TextStyle(
                      fontWeight: item.read ? FontWeight.w600 : FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                  if (item.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      item.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (item.createdAt != null)
                    Text(
                      DateFormat('d MMM · HH:mm').format(item.createdAt!),
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (!item.read)
              Container(
                margin: const EdgeInsets.only(top: 4, left: 4),
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: AppColors.coral,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
