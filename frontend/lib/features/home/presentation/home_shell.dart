import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/update/app_update_service.dart';
import '../../billing/presentation/invoices_screen.dart';
import '../../chat/presentation/chat_list_screen.dart';
import '../../profile/domain/profile.dart';
import '../../shifts/presentation/browse_shifts_screen.dart';
import '../../shifts/presentation/my_shifts_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../training/presentation/training_screen.dart';
import 'widgets/floating_nav_bar.dart';
import 'widgets/update_banner.dart';

final homeShellTabIndexProvider = StateProvider<int>((ref) => 0);

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  bool _requiredUpdateDialogShown = false;

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final isStaff = profile?.role == UserRole.staff;

    // A required update blocks with a dialog rather than a banner — shown
    // at most once per HomeShell mount.
    ref.listen(appUpdateStatusProvider, (_, next) {
      final info = next.valueOrNull;
      if (info != null && info.status == AppUpdateStatus.required && !_requiredUpdateDialogShown) {
        _requiredUpdateDialogShown = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showRequiredUpdateDialog(context, info.downloadUrl);
        });
      }
    });

    final tabs = [
      if (isStaff) const BrowseShiftsScreen(),
      const MyShiftsScreen(),
      const ChatListScreen(),
      if (!isStaff) const InvoicesScreen(),
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
          label: 'Invoices',
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

    final isAdminPreview = ref.watch(adminMarketplacePreviewProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            if (isAdminPreview)
              Container(
                color: const Color(0xFF1B2A4A),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.admin_panel_settings_outlined, color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Admin Preview Mode (Marketplace View)',
                        style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () {
                        ref.read(adminMarketplacePreviewProvider.notifier).state = false;
                        context.go('/admin');
                      },
                      child: const Text('Back to Admin', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.logout_rounded, color: Colors.white, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Sign out',
                      onPressed: () {
                        ref.read(adminMarketplacePreviewProvider.notifier).state = false;
                        ref.read(authRepositoryProvider).signOut();
                      },
                    ),
                  ],
                ),
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
