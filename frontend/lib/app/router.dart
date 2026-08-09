import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/admin/presentation/admin_review_screen.dart';
import '../features/admin/presentation/admin_user_detail_screen.dart';
import '../features/auth/presentation/change_password_screen.dart';
import '../features/auth/presentation/forgot_password_screen.dart';
import '../features/auth/presentation/role_select_screen.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/auth/presentation/sign_up_screen.dart';
import '../features/settings/presentation/settings_screen.dart';
import '../features/onboarding/presentation/onboarding_router_screen.dart';
import '../features/chat/presentation/chat_list_screen.dart';
import '../features/chat/presentation/chat_screen.dart';
import '../features/documents/presentation/dbs_upload_screen.dart';
import '../features/home/presentation/home_shell.dart';
import '../features/home/presentation/splash_screen.dart';
import '../features/notifications/presentation/notifications_screen.dart';
import '../features/training/presentation/training_module_screen.dart';
import '../features/training/presentation/training_quiz_screen.dart';
import '../features/profile/domain/profile.dart';
import '../features/profile/presentation/edit_profile_screen.dart';
import '../features/profile/presentation/public_profile_screen.dart';
import '../features/shifts/presentation/post_shift_screen.dart';
import '../features/shifts/presentation/shift_detail_screen.dart';
import '../core/analytics/analytics_service.dart';
import 'providers.dart';

/// Bridges Riverpod's authStateProvider/ownProfileProvider into go_router's
/// Listenable-based refresh model, so a sign-in/sign-out/role-set anywhere
/// in the app immediately re-runs [redirect] instead of waiting for the
/// next manual navigation.
class _RouterRefreshNotifier extends ChangeNotifier {
  _RouterRefreshNotifier(Ref ref) {
    ref.listen(authStateProvider, (_, __) => notifyListeners());
    ref.listen(ownProfileProvider, (_, __) => notifyListeners());
    ref.listen(isAdminProvider, (_, __) => notifyListeners());
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final refresh = _RouterRefreshNotifier(ref);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    observers: [ref.watch(analyticsObserverProvider)],
    redirect: (context, state) {
      final onSplash = state.matchedLocation == '/splash';
      final authState = ref.read(authStateProvider);
      if (!authState.hasValue) return onSplash ? null : '/splash';

      final user = authState.value;
      final loggingIn = state.matchedLocation == '/sign-in';
      final signingUp = state.matchedLocation == '/sign-up';
      final resettingPassword = state.matchedLocation == '/forgot-password';

      if (user == null) {
        return (loggingIn || signingUp || resettingPassword) ? null : '/sign-in';
      }

      // Admin accounts (Firebase "admin" custom claim, set out-of-band —
      // see backend/services/core/function/documents.go isAdmin) skip the
      // normal nursery/staff role-select and onboarding gate entirely —
      // they have no marketplace role at all, just the review queue.
      final isAdminState = ref.read(isAdminProvider);
      final onAdmin = state.matchedLocation.startsWith('/admin');
      if (isAdminState.valueOrNull == true) {
        return onAdmin ? null : '/admin';
      }
      if (!isAdminState.hasValue) return onSplash ? null : '/splash';

      final profileState = ref.read(ownProfileProvider);
      final profile = profileState.valueOrNull;
      final onRoleSelect = state.matchedLocation == '/role-select';
      final onOnboarding = state.matchedLocation == '/onboarding';

      if (profile == null) {
        if (profileState.isLoading) return onSplash ? null : '/splash';
        return onRoleSelect ? null : '/role-select';
      }

      if (profile.role == UserRole.none) {
        return onRoleSelect ? null : '/role-select';
      }
      // The one hard gate before entering the app — full app spec §1.4:
      // "Basics" (name/phone/[address for nursery]) must be complete.
      // Everything else in the wizard is finish-it-later via a banner.
      if (!profile.hasCompletedBasics) {
        return onOnboarding ? null : '/onboarding';
      }
      // Basics done — let the wizard keep running so the user completes
      // experience / DBS steps before landing in the app. Only redirect
      // away from /onboarding if the user explicitly navigates elsewhere
      // (i.e. they called context.go('/home') from the wizard itself).
      if (onOnboarding) return null;
      if (loggingIn || signingUp || onRoleSelect || onSplash) return '/home';
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, __) => '/home'),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/sign-in', builder: (_, __) => const SignInScreen()),
      GoRoute(path: '/sign-up', builder: (_, __) => const SignUpScreen()),
      GoRoute(path: '/forgot-password', builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(path: '/role-select', builder: (_, __) => const RoleSelectScreen()),
      GoRoute(path: '/admin', builder: (_, __) => const AdminReviewScreen()),
      GoRoute(
        path: '/admin/users/:uid',
        builder: (_, state) => AdminUserDetailScreen(uid: state.pathParameters['uid']!),
      ),
      GoRoute(path: '/onboarding', builder: (_, __) => const OnboardingRouterScreen()),
      GoRoute(path: '/home', builder: (_, __) => const HomeShell()),
      GoRoute(path: '/notifications', builder: (_, __) => const NotificationsScreen()),
      // Quiz sits under the module so a back gesture from the quiz returns to
      // the module rather than the tab root.
      GoRoute(
        path: '/training/:moduleId',
        builder: (_, state) => TrainingModuleScreen(moduleId: state.pathParameters['moduleId']!),
        routes: [
          GoRoute(
            path: 'quiz',
            builder: (_, state) => TrainingQuizScreen(moduleId: state.pathParameters['moduleId']!),
          ),
        ],
      ),
      GoRoute(path: '/profile/edit', builder: (_, __) => const EditProfileScreen()),
      GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
      GoRoute(
        path: '/settings/change-password',
        builder: (_, __) => const ChangePasswordScreen(),
      ),
      GoRoute(path: '/profile/dbs', builder: (_, __) => const DbsUploadScreen()),
      GoRoute(
        path: '/profile/:uid',
        builder: (_, state) => PublicProfileScreen(uid: state.pathParameters['uid']!),
      ),
      GoRoute(path: '/shifts/new', builder: (_, __) => const PostShiftScreen()),
      GoRoute(
        path: '/shifts/:id',
        builder: (_, state) => ShiftDetailScreen(shiftId: state.pathParameters['id']!),
      ),
      GoRoute(path: '/chats', builder: (_, __) => const ChatListScreen()),
      GoRoute(
        path: '/chats/:sessionId',
        builder: (_, state) => ChatScreen(sessionId: state.pathParameters['sessionId']!),
      ),
    ],
  );
});
