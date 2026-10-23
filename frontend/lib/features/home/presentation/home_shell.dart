import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/update/app_update_service.dart';
import '../../billing/presentation/subscriptions_screen.dart';
import '../../chat/presentation/chat_list_screen.dart';
import '../../profile/domain/profile.dart';
import '../../shifts/presentation/browse_shifts_screen.dart';
import '../../shifts/presentation/my_shifts_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../training/presentation/training_screen.dart';
import 'widgets/email_verification_banner.dart';
import 'widgets/floating_nav_bar.dart';
import 'widgets/profile_completion_banner.dart';
import 'widgets/update_banner.dart';

final homeShellTabIndexProvider = StateProvider<int>((ref) => 0);
final sessionBannerDismissedProvider = StateProvider<bool>((ref) => false);
final sessionVerifyBannerDismissedProvider = StateProvider<bool>((ref) => false);
final sessionUpdateBannerDismissedProvider = StateProvider<bool>((ref) => false);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _bannerDismissed = false;
  bool _verifyBannerDismissed = false;
  bool _updateBannerDismissed = false;
  bool _requiredUpdateDialogShown = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final isStaff = profile?.role == UserRole.staff;
    final emailVerified = ref.watch(emailVerifiedProvider).valueOrNull ?? true;

    // A required update blocks with a dialog rather than a banner — shown
    // at most once per HomeShell mount (fetch itself only runs once, since
    // appUpdateStatusProvider isn't autoDispose/family, so re-triggering
    // isn't a concern here).
    ref.listen(appUpdateStatusProvider, (_, next) {
      final info = next.valueOrNull;
      if (info != null && info.status == AppUpdateStatus.required && !_requiredUpdateDialogShown) {
        _requiredUpdateDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showRequiredUpdateDialog(context, info.downloadUrl);
        });
      }
    });
    final updateInfo = ref.watch(appUpdateStatusProvider).valueOrNull;

    final bannerDismissed = ref.watch(sessionBannerDismissedProvider);
    final verifyDismissed = ref.watch(sessionVerifyBannerDismissedProvider);
    final updateDismissed = ref.watch(sessionUpdateBannerDismissedProvider);

    final tabs = [
      if (isStaff) const BrowseShiftsScreen(),
      const MyShiftsScreen(),
      const ChatListScreen(),
      if (!isStaff) const SubscriptionsScreen(),
      if (isStaff) const TrainingScreen(),
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
      if (!isStaff)
        const NavItem(
          icon: Icons.receipt_long_outlined,
          selectedIcon: Icons.receipt_long_rounded,
          label: 'Billing',
        ),
      if (isStaff)
        const NavItem(
          icon: Icons.school_outlined,
          selectedIcon: Icons.school_rounded,
          label: 'Training',
        ),
      const NavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'Profile'),
    ];

    final currentIndex = ref.watch(homeShellTabIndexProvider);
    final activeIndex = currentIndex >= tabs.length ? 0 : currentIndex;

    final showBanner = !bannerDismissed &&
        profile != null &&
        profile.hasIncompleteOptionalSteps &&
        // If nursery has already filled in description or company name, don't nag
        (isStaff || profile.description.trim().isEmpty);

    return Scaffold(
      // HomeShell has no AppBar of its own (each tab supplies one), so
      // without SafeArea the completion banner and tab content render
      // straight under the status bar/notch instead of below it.
      body: SafeArea(
        child: Column(
          children: [
            if (!emailVerified && !verifyDismissed)
              EmailVerificationBanner(
                onDismiss: () => ref.read(sessionVerifyBannerDismissedProvider.notifier).state = true,
              ),
            if (updateInfo != null &&
                updateInfo.status == AppUpdateStatus.optional &&
                !updateDismissed)
              UpdateAvailableBanner(
                downloadUrl: updateInfo.downloadUrl,
                onDismiss: () => ref.read(sessionUpdateBannerDismissedProvider.notifier).state = true,
              ),
            if (showBanner)
              ProfileCompletionBanner(
                profile: profile,
                onDismiss: () => ref.read(sessionBannerDismissedProvider.notifier).state = true,
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
                child: KeyedSubtree(key: ValueKey(activeIndex), child: tabs[activeIndex]),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: FloatingNavBar(
        selectedIndex: activeIndex,
        onDestinationSelected: (i) => ref.read(homeShellTabIndexProvider.notifier).state = i,
        items: items,
      ),
    );
  }
}
