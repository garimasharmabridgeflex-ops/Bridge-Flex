import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../chat/presentation/chat_list_screen.dart';
import '../../profile/domain/profile.dart';
import '../../shifts/presentation/browse_shifts_screen.dart';
import '../../shifts/presentation/my_shifts_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../training/presentation/training_screen.dart';
import 'widgets/email_verification_banner.dart';
import 'widgets/floating_nav_bar.dart';
import 'widgets/profile_completion_banner.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;
  bool _bannerDismissed = false;
  bool _verifyBannerDismissed = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final isStaff = profile?.role == UserRole.staff;
    final emailVerified = ref.watch(emailVerifiedProvider).valueOrNull ?? true;

    final tabs = [
      if (isStaff) const BrowseShiftsScreen(),
      const MyShiftsScreen(),
      const ChatListScreen(),
      const TrainingScreen(),
      const ProfileScreen(),
    ];
    final items = [
      if (isStaff)
        const NavItem(icon: Icons.search_outlined, selectedIcon: Icons.search_rounded, label: 'Browse'),
      NavItem(
        icon: Icons.event_note_outlined,
        selectedIcon: Icons.event_note_rounded,
        label: isStaff ? 'My shifts' : 'Shifts',
      ),
      const NavItem(
        icon: Icons.chat_bubble_outline_rounded,
        selectedIcon: Icons.chat_bubble_rounded,
        label: 'Messages',
      ),
      const NavItem(
        icon: Icons.school_outlined,
        selectedIcon: Icons.school_rounded,
        label: 'Training',
      ),
      const NavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Profile'),
    ];

    if (_index >= tabs.length) _index = 0;

    final showBanner =
        !_bannerDismissed && profile != null && profile.hasIncompleteOptionalSteps;

    return Scaffold(
      // HomeShell has no AppBar of its own (each tab supplies one), so
      // without SafeArea the completion banner and tab content render
      // straight under the status bar/notch instead of below it.
      body: SafeArea(
        child: Column(
          children: [
            if (!emailVerified && !_verifyBannerDismissed)
              EmailVerificationBanner(
                onDismiss: () => setState(() => _verifyBannerDismissed = true),
              ),
            if (showBanner)
              ProfileCompletionBanner(
                profile: profile,
                onDismiss: () => setState(() => _bannerDismissed = true),
              ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: KeyedSubtree(key: ValueKey(_index), child: tabs[_index]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        items: items,
        // Both reference designs put the primary "create" action as a
        // raised center button rather than a plain tab — for Bridge Flex
        // that's "post a shift", which only makes sense for nurseries.
        centerAction: isStaff
            ? null
            : NavCenterAction(
                icon: Icons.add_rounded,
                tooltip: 'Post shift',
                onTap: () => context.push('/shifts/new'),
              ),
      ),
    );
  }
}
