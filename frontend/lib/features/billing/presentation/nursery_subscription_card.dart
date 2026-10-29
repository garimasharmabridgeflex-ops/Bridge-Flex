import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/live/live_refresh.dart';
import '../domain/billing_models.dart';

final nurserySubscriptionProvider = FutureProvider.autoDispose<({NurserySubscription subscription, TrialCountdown trial})>((ref) {
  // Plan changes and trial dates are set by an admin, so this rides the live
  // heartbeat rather than waiting for the app to be restarted.
  ref.watch(liveTickProvider);
  return ref.watch(billingRepositoryProvider).getNurserySubscription();
});

final availablePlansProvider = FutureProvider.autoDispose<List<Plan>>((ref) {
  ref.watch(liveTickProvider);
  return ref.watch(billingRepositoryProvider).getPlans();
});

class NurserySubscriptionCard extends ConsumerWidget {
  const NurserySubscriptionCard({super.key});

  void _showUpgradeSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final plansAsync = ref.watch(availablePlansProvider);
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Membership Plans', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                const Text(
                  'Choose a membership plan for your nursery. Invoices are settled via secure bank transfer.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: AppSpacing.md),
                plansAsync.when(
                  loading: () => const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
                  error: (e, _) => Text('Error loading plans: $e'),
                  data: (plans) => Column(
                    children: plans.where((p) => p.id != 'trial').map((plan) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(color: AppColors.teal.withValues(alpha: 0.3)),
                        ),
                        child: ListTile(
                          title: Text(plan.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                          subtitle: Text(plan.description, style: const TextStyle(fontSize: 12)),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(plan.priceFormatted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.teal)),
                              Text(plan.billingInterval == 'month' ? '/month (ex-VAT)' : '/booking', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                            ],
                          ),
                          onTap: () {
                            Navigator.of(ctx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('To activate ${plan.name}, our finance team will contact your registered billing email.'),
                                backgroundColor: AppColors.teal,
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subAsync = ref.watch(nurserySubscriptionProvider);

    return subAsync.when(
      loading: () => Container(
        height: 64,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0)),
        ),
        child: const Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B2A4A)),
        ),
      ),
      error: (_, __) => Card(
        elevation: 0,
        margin: const EdgeInsets.only(bottom: AppSpacing.sm),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        child: ListTile(
          leading: const Icon(Icons.card_membership_rounded, color: Color(0xFF2563EB)),
          title: const Text('14-Day Free Trial Active', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
          subtitle: const Text('Tap to view membership plans & pricing', style: TextStyle(fontSize: 12)),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
          onTap: () => context.push('/billing/subscriptions'),
        ),
      ),
      data: (data) {
        final sub = data.subscription;
        final trial = data.trial;
        final profile = ref.watch(ownProfileProvider).valueOrNull;
        final isApproved = profile?.nurseryApprovalStatus == 'approved';

        if (sub.isTrialing) {
          final isExpired = isApproved && trial.isExpired;
          final color = isExpired ? AppColors.coral : AppColors.teal;

          return Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: color.withValues(alpha: 0.3)),
            ),
            color: color.withValues(alpha: 0.06),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              !isApproved
                                  ? Icons.hourglass_top_rounded
                                  : (isExpired ? Icons.timer_off_outlined : Icons.timer_outlined),
                              color: color,
                              size: 19,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                !isApproved
                                    ? '14-Day Free Trial'
                                    : (isExpired ? 'Free Trial Expired' : '14-Day Free Trial'),
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: color),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          !isApproved
                              ? 'Pending Approval'
                              : (isExpired ? 'Expired' : '${trial.daysRemaining} days left'),
                          style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    !isApproved
                        ? 'Your 14-day free trial will activate automatically upon compliance verification of your nursery account. All 14 days will be preserved.'
                        : (isExpired
                            ? 'Your 14-day free trial has expired. Select a membership plan or use Pay As You Go to continue posting shifts.'
                            : 'Explore available practitioners and post shifts. Staffing hours worked are billed separately at the standard rate.'),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  if (isApproved && !isExpired) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Trial Period: ${sub.trialStartDate != null ? DateFormat('d MMM yyyy').format(sub.trialStartDate!) : 'Active'} → ${sub.trialEndDate != null ? DateFormat('d MMM yyyy').format(sub.trialEndDate!) : '${trial.daysRemaining} days left'}',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: () => context.push('/billing/subscriptions'),
                          style: FilledButton.styleFrom(
                            backgroundColor: color,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: const Text('Subscription Options & Upgrade', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () => context.push('/billing/invoices'),
                        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                        child: const Text('Invoices', style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        }

        // Active subscription or Pay As You Go
        return Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(sub.planName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 2),
                    Text(
                      'Membership active · Renews ${sub.currentPeriodEnd.day}/${sub.currentPeriodEnd.month}/${sub.currentPeriodEnd.year}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                OutlinedButton(
                  onPressed: () => context.push('/billing/invoices'),
                  child: const Text('Invoices'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
