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
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Messages',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: sessionsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF1B2A4A)),
        ),
        error: (e, _) => Center(child: Text('$e')),
        data: (sessions) {
          if (sessions.isEmpty) {
            return const EmptyState(
              icon: Icons.chat_bubble_outline_rounded,
              title: 'No conversations yet',
              subtitle: 'A chat thread opens automatically once a shift booking is confirmed.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
            itemCount: sessions.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
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
    final name = peer.valueOrNull?.name ?? '…';

    return GestureDetector(
      onTap: () => context.push('/chats/${session.id}'),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x060F172A),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: const Color(0xFF1B2A4A).withValues(alpha: 0.08),
              child: Text(
                name.isNotEmpty ? name[0].toUpperCase() : '?',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Color(0xFF1B2A4A), fontSize: 16),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5, color: Color(0xFF0F172A)),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    DateFormat('d MMM · HH:mm').format(session.lastMessageAt),
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1), size: 20),
          ],
        ),
      ),
    );
  }
}
