import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/api/api_exception.dart';
import '../../profile/domain/profile.dart';

class RoleSelectScreen extends ConsumerStatefulWidget {
  const RoleSelectScreen({super.key});

  @override
  ConsumerState<RoleSelectScreen> createState() => _RoleSelectScreenState();
}

class _RoleSelectScreenState extends ConsumerState<RoleSelectScreen> {
  bool _loading = false;

  Future<void> _choose(UserRole role) async {
    setState(() => _loading = true);
    try {
      await ref.read(profileRepositoryProvider).setRole(role);
      ref.invalidate(ownProfileProvider);
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.message),
            backgroundColor: const Color(0xFF1B2A4A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // App Badge / Brand Icon
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2A4A),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x201B2A4A),
                          blurRadius: 16,
                          offset: Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.diversity_3_rounded,
                      color: Colors.white,
                      size: 26,
                    ),
                  ).animate().fadeIn(duration: 300.ms).scale(begin: const Offset(0.9, 0.9)),
                  const SizedBox(height: 24),

                  const Text(
                    "Welcome to KFlex",
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF2563EB),
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    "How will you be using\nthe platform?",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0F172A),
                      height: 1.2,
                      letterSpacing: -0.5,
                    ),
                  ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.08, end: 0),
                  const SizedBox(height: 10),
                  const Text(
                    'Select your account type to continue. This configures your shifts, bookings, and compliance features.',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFF64748B),
                      height: 1.45,
                    ),
                  ).animate().fadeIn(delay: 80.ms, duration: 350.ms),
                  const SizedBox(height: 32),

                  // Option 1: Nursery
                  _RoleCard(
                    icon: Icons.corporate_fare_rounded,
                    title: "I'm a Nursery Manager",
                    subtitle: 'Post last-minute nursery shifts, review verified practitioners, and manage timesheets.',
                    accentColor: const Color(0xFF1B2A4A),
                    loading: _loading,
                    onTap: () => _choose(UserRole.nursery),
                  ).animate().fadeIn(delay: 140.ms, duration: 350.ms).slideY(begin: 0.05, end: 0),
                  const SizedBox(height: 16),

                  // Option 2: Staff
                  _RoleCard(
                    icon: Icons.badge_rounded,
                    title: "I'm a Childcare Practitioner",
                    subtitle: 'Browse qualified nursery shifts nearby, complete EYFS training, and earn flexible pay.',
                    accentColor: const Color(0xFF2563EB),
                    loading: _loading,
                    onTap: () => _choose(UserRole.staff),
                  ).animate().fadeIn(delay: 200.ms, duration: 350.ms).slideY(begin: 0.05, end: 0),

                  const SizedBox(height: 28),
                  Center(
                    child: TextButton.icon(
                      onPressed: () async {
                        await ref.read(firebaseAuthProvider).signOut();
                      },
                      icon: const Icon(Icons.logout_rounded, size: 16, color: Color(0xFF64748B)),
                      label: const Text(
                        'Sign out / Use another account',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ),
                  ),

                  if (_loading) ...[
                    const SizedBox(height: 28),
                    const Center(
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: Color(0xFF1B2A4A),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
    required this.loading,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color accentColor;
  final VoidCallback onTap;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080F172A),
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: loading ? null : onTap,
          borderRadius: BorderRadius.circular(20),
          hoverColor: const Color(0xFFF8FAFC),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withValues(alpha: 0.15)),
                  ),
                  child: Icon(icon, color: accentColor, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: const Color(0xFF94A3B8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

