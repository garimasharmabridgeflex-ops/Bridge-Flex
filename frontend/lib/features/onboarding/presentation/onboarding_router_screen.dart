import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../profile/domain/profile.dart';
import 'nursery_onboarding_screen.dart';
import 'staff_onboarding_screen.dart';

/// Dispatches to the role-appropriate onboarding wizard — full app spec
/// §1.2 (staff) / §1.3 (nursery). The router only sends signed-in users
/// with a role but incomplete Basics here, so `profile` and `profile.role`
/// are always non-null/non-none by the time this builds.
class OnboardingRouterScreen extends ConsumerWidget {
  const OnboardingRouterScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return profile.role == UserRole.nursery
        ? const NurseryOnboardingScreen()
        : const StaffOnboardingScreen();
  }
}
