import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';
import '../data/chat_models.dart';

final chatSessionsProvider = FutureProvider.autoDispose<List<ChatSession>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Future.value(<ChatSession>[]);
  return ref.watch(chatRepositoryProvider).fetchSessions();
});

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionsAsync = ref.watch(chatSessionsProvider);
    final selfUid = ref.watch(authStateProvider).valueOrNull?.uid ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      body: sessionsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('$e')),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No conversations yet',
              subtitle: 'A chat opens automatically once a shift is booked.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (context, i) {
              final session = sessions[i];
              final otherUid = session.otherParticipant(selfUid);
              return _SessionTile(session: session, otherUid: otherUid)
                  .animate()
                  .fadeIn(delay: (30 * i).ms, duration: 250.ms);
            },
          );
        },
      ),
    );
  }
}

final _peerNameProvider = FutureProvider.autoDispose.family((ref, String uid) {
  return ref.watch(profileRepositoryProvider).fetchPublicProfile(uid);
});

class _SessionTile extends ConsumerWidget {
  const _SessionTile({required this.session, required this.otherUid});

  final ChatSession session;
  final String otherUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peer = ref.watch(_peerNameProvider(otherUid));
    final scheme = Theme.of(context).colorScheme;
    final name = peer.valueOrNull?.name ?? '…';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.primary.withValues(alpha: 0.12),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(DateFormat('d MMM · HH:mm').format(session.lastMessageAt)),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => context.push('/chats/${session.id}'),
      ),
    );
  }
}
