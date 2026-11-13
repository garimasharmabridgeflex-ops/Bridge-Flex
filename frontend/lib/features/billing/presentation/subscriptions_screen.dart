import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../profile/domain/profile.dart';
import '../domain/billing_models.dart';
import 'nursery_subscription_card.dart';

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen>
    with WidgetsBindingObserver {
  String? _busyPlanId;
  bool _busyPortal = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Stripe Checkout/Portal open in an in-app browser tab. Coming back to the
  /// app is the signal that the payment may have completed, so refresh the
  /// membership — silently, since the status card keeps its last values.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(nurserySubscriptionProvider);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFF1B2A4A), content: Text(message)),
    );
  }

  Future<void> _startCheckout(String planId) async {
    if (_busyPlanId != null) return;
    setState(() => _busyPlanId = planId);
    try {
      final result = await ref
          .read(billingRepositoryProvider)
          .createCheckoutSession(planId: planId);
      if (!mounted) return;
      if (result.url == null) {
        // Existing card subscription retuned in place — no redirect needed.
        ref.invalidate(nurserySubscriptionProvider);
        _showMessage('Your membership has been updated.');
        return;
      }
      final uri = Uri.parse(result.url!);
      var opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!opened) {
        _showMessage('Could not open the secure payment page.');
      }
    } on ApiException catch (e) {
      _showMessage(e.code == 'PLAN_NOT_CONFIGURED' || e.code == 'PAYMENTS_NOT_CONFIGURED'
          ? 'Card payments are being switched on — please try again shortly.'
          : e.message);
    } catch (_) {
      _showMessage('Could not start checkout. Please try again.');
    } finally {
      if (mounted) setState(() => _busyPlanId = null);
    }
  }

  Future<void> _openPortal() async {
    if (_busyPortal) return;
    setState(() => _busyPortal = true);
    try {
      final url = await ref.read(billingRepositoryProvider).createBillingPortalSession();
      if (!mounted) return;
      final uri = Uri.parse(url);
      var opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) {
        opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
      if (!opened) _showMessage('Could not open the billing portal.');
    } on ApiException catch (e) {
      _showMessage(e.message);
    } catch (_) {
      _showMessage('Could not open the billing portal. Please try again.');
    } finally {
      if (mounted) setState(() => _busyPortal = false);
    }
  }

  /// "Manage billing" opens Stripe's hosted portal for card-paying nurseries:
  /// update the card, download receipts, or cancel. Nothing about the card is
  /// ever handled in the app.
  Widget _manageBillingButton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busyPortal ? null : _openPortal,
          icon: _busyPortal
              ? const SizedBox(
                  height: 14,
                  width: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.credit_card_rounded, size: 16),
          label: const Text(
            'Manage billing',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFF1B2A4A),
            side: const BorderSide(color: Color(0xFFCBD5E1)),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(ownProfileProvider).valueOrNull;
    final isNursery = profile?.role == UserRole.nursery;
    final plansAsync = ref.watch(availablePlansProvider);
    final subAsync = isNursery ? ref.watch(nurserySubscriptionProvider) : null;
    final currentPlanId = subAsync?.valueOrNull?.subscription.planId ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        automaticallyImplyLeading: true,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Back',
                onPressed: () => context.pop(),
              )
            : null,
        backgroundColor: const Color(0xFFF8FAFC),
        elevation: 0,
        scrolledUnderElevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF0F172A)),
        title: Text(
          isNursery ? 'Membership & Subscriptions' : 'Practitioner Access',
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Current Membership Status Banner ───────────────────────────
            if (isNursery) ...[
              subAsync?.when(skipLoadingOnRefresh: true,
                    loading: () => Container(
                      height: 120,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF1B2A4A)),
                      ),
                    ),
                    error: (e, _) => _StatusCard(
                      title: 'Nursery Subscription',
                      subtitle: 'Active 14-day free trial on approved registration',
                      badge: 'Trial Active',
                      badgeColor: const Color(0xFF2563EB),
                      icon: Icons.timer_outlined,
                      details: 'Explore available practitioners and post shifts with zero upfront commitment.',
                    ),
                    data: (data) {
                      final sub = data.subscription;
                      final trial = data.trial;
                      final isApproved = profile?.nurseryApprovalStatus == 'approved';

                      if (sub.isTrialing) {
                        if (!isApproved) {
                          return const _StatusCard(
                            title: '14-Day Free Trial (Pending Approval)',
                            subtitle: 'Activates upon admin verification',
                            badge: 'Pending Verification',
                            badgeColor: Color(0xFFF59E0B),
                            icon: Icons.hourglass_top_rounded,
                            details:
                                'Your 14-day free trial will activate automatically once your nursery account and Ofsted details are verified. All 14 trial days will be preserved.',
                          );
                        }
                        return _StatusCard(
                          title: '14-Day Free Trial',
                          subtitle: trial.isExpired ? 'Trial has ended' : '${trial.daysRemaining} days remaining',
                          badge: trial.isExpired ? 'Expired' : '${trial.daysRemaining} Days Left',
                          badgeColor: trial.isExpired ? const Color(0xFFEF4444) : const Color(0xFF2563EB),
                          icon: trial.isExpired ? Icons.timer_off_outlined : Icons.timer_outlined,
                          details: trial.isExpired
                              ? 'Your free trial has concluded. Select an ongoing membership plan or choose Pay As You Go to continue posting shifts.'
                              : 'Your nursery is currently enjoying full access to the Bridge-Flex marketplace. Staffing hours worked are billed separately.',
                        );
                      }
                      if (sub.isPastDue) {
                        return Column(
                          children: [
                            const _StatusCard(
                              title: 'Payment failed',
                              subtitle: 'Your card was declined',
                              badge: 'Past due',
                              badgeColor: Color(0xFFEF4444),
                              icon: Icons.credit_card_off_rounded,
                              details:
                                  'Update your card to keep posting shifts. Stripe retries the payment automatically, and your membership stays paused until it succeeds.',
                            ),
                            _manageBillingButton(),
                          ],
                        );
                      }

                      if (sub.status == 'cancelled' || sub.status == 'expired') {
                        return Column(
                          children: [
                            _StatusCard(
                              title: sub.planName,
                              subtitle: 'Membership ended',
                              badge: 'Ended',
                              badgeColor: const Color(0xFF64748B),
                              icon: Icons.timer_off_outlined,
                              details:
                                  'Choose a plan below to start posting shifts again. Your invoices and completed bookings are unaffected.',
                            ),
                            if (sub.paidByCard) _manageBillingButton(),
                          ],
                        );
                      }

                      return Column(
                        children: [
                          _StatusCard(
                            title: sub.planName,
                            subtitle: sub.cancelAtPeriodEnd
                                ? 'Ends ${DateFormat('d MMMM yyyy').format(sub.currentPeriodEnd)}'
                                : 'Renews ${DateFormat('d MMMM yyyy').format(sub.currentPeriodEnd)}',
                            badge: sub.cancelAtPeriodEnd ? 'Cancelling' : 'Active',
                            badgeColor: sub.cancelAtPeriodEnd
                                ? const Color(0xFFF59E0B)
                                : const Color(0xFF10B981),
                            icon: sub.cancelAtPeriodEnd
                                ? Icons.event_busy_rounded
                                : Icons.verified_rounded,
                            details: sub.paidByCard
                                ? 'Paid by card through Stripe. Update your card or cancel any time in Manage billing.'
                                : 'Membership is active. Update your payment card any time in Manage billing.',
                          ),
                          if (sub.paidByCard) _manageBillingButton(),
                        ],
                      );
                    },
                  ) ??
                  const SizedBox.shrink(),
            ] else ...[
              _StatusCard(
                title: 'Practitioner Membership',
                subtitle: 'Early years practitioner platform access',
                badge: 'Active',
                badgeColor: const Color(0xFF10B981),
                icon: Icons.check_circle_outline_rounded,
                details:
                    'Practitioners do not pay platform subscriptions on Bridge-Flex. You keep your full hourly earnings plus accrued 12.07% statutory holiday pay.',
              ),
            ],
            if (isNursery) ...[
              const SizedBox(height: 24),

              // ── Section Header ─────────────────────────────────────────────
              const Text(
                'NURSERY MEMBERSHIP PLANS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF64748B),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 12),

              // ── Plans List ─────────────────────────────────────────────────
              plansAsync.when(skipLoadingOnRefresh: true,
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFF1B2A4A)),
                  ),
                ),
                error: (_, _) => _FallbackPlansList(
                  isNursery: isNursery,
                  currentPlanId: currentPlanId,
                  busyPlanId: _busyPlanId,
                  onSelect: _startCheckout,
                ),
                data: (plans) {
                  if (plans.isEmpty) {
                    return _FallbackPlansList(
                      isNursery: isNursery,
                      currentPlanId: currentPlanId,
                      busyPlanId: _busyPlanId,
                      onSelect: _startCheckout,
                    );
                  }
                  return Column(
                    children: plans.map((plan) {
                      return _PlanCard(
                        plan: plan,
                        isNursery: isNursery,
                        isCurrent: plan.id == currentPlanId,
                        busy: _busyPlanId == plan.id,
                        onSelect: () => _startCheckout(plan.id),
                      );
                    }).toList(),
                  );
                },
              ),
                          ] else ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Practitioner Access Benefits',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 14),
                    _PractitionerBenefitRow(
                      icon: Icons.money_off_rounded,
                      title: 'Zero Platform Commission',
                      desc: 'You keep 100% of your hourly rate with no hidden fees.',
                    ),
                    const SizedBox(height: 12),
                    _PractitionerBenefitRow(
                      icon: Icons.beach_access_rounded,
                      title: '12.07% Statutory Holiday Pay',
                      desc: 'Accrued automatically on every completed shift and clearly itemized on weekly payslips.',
                    ),
                    const SizedBox(height: 12),
                    _PractitionerBenefitRow(
                      icon: Icons.school_outlined,
                      title: 'Complimentary EYFS Modules',
                      desc: 'Unlimited free access to continuous professional development modules and certificates.',
                    ),
                    const SizedBox(height: 12),
                    _PractitionerBenefitRow(
                      icon: Icons.verified_user_outlined,
                      title: 'Direct Weekly Payouts',
                      desc: 'Settled directly via bank transfer every Friday upon nursery timesheet sign-off.',
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeColor,
    required this.icon,
    required this.details,
  });

  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;
  final IconData icon;
  final String details;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x060F172A),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: badgeColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF0F172A),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: badgeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              color: badgeColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            details,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF475569), height: 1.45),
          ),
        ],
      ),
    ).animate().fadeIn(duration: 200.ms);
  }
}

class _PlanCard extends StatelessWidget {
  const _PlanCard({
    required this.plan,
    required this.isNursery,
    required this.onSelect,
    this.isCurrent = false,
    this.busy = false,
  });

  final Plan plan;
  final bool isNursery;
  final VoidCallback onSelect;
  final bool isCurrent;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final isPremium = plan.id == 'premium';
    final isStandard = plan.id == 'standard';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isPremium
              ? const Color(0xFF2563EB)
              : (isStandard ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0)),
          width: isPremium ? 2 : 1,
        ),
        boxShadow: [
          if (isPremium)
            const BoxShadow(
              color: Color(0x142563EB),
              blurRadius: 16,
              offset: Offset(0, 4),
            )
          else
            const BoxShadow(
              color: Color(0x060F172A),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                plan.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF0F172A),
                ),
              ),
              if (isPremium)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2563EB),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'MOST POPULAR',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            plan.description,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                plan.priceFormatted,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                plan.billingInterval == 'month'
                    ? '/ month (ex-VAT)'
                    : (plan.billingInterval == 'per_booking' ? '/ booking (ex-VAT)' : ' (14 days)'),
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFFF1F5F9), height: 1),
          const SizedBox(height: 12),
          for (final benefit in plan.benefits) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_rounded, size: 16, color: Color(0xFF10B981)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      benefit,
                      style: const TextStyle(fontSize: 12.5, color: Color(0xFF334155), fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: !isNursery
                  ? () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          backgroundColor: Color(0xFF1B2A4A),
                          content: Text(
                            'This plan is for nurseries. Staff practitioners enjoy 100% free lifetime access.',
                          ),
                        ),
                      );
                    }
                  : (busy || isCurrent || plan.billingInterval == 'none' ? null : onSelect),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1B2A4A),
                foregroundColor: Colors.white,
                disabledBackgroundColor: const Color(0xFFE2E8F0),
                disabledForegroundColor: const Color(0xFF64748B),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.pill)),
              ),
              child: busy
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      !isNursery
                          ? 'Learn More'
                          : isCurrent
                              ? 'Current plan'
                              : plan.billingInterval == 'none'
                                  ? 'Included with approval'
                                  : 'Continue to secure checkout',
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FallbackPlansList extends StatelessWidget {
  const _FallbackPlansList({
    required this.isNursery,
    required this.currentPlanId,
    required this.busyPlanId,
    required this.onSelect,
  });

  final bool isNursery;
  final String currentPlanId;
  final String? busyPlanId;
  final void Function(String planId) onSelect;

  @override
  Widget build(BuildContext context) {
    final defaultSeedPlans = [
      const Plan(
        id: 'standard',
        name: 'Standard Subscription',
        description: 'Designed for nurseries that regularly require temporary early years cover',
        pricePence: 19900,
        billingInterval: 'month',
        bookingAllowance: 0,
        trialDays: 0,
        active: true,
        benefits: [
          'Unlimited staff bookings per month',
          'Access to fully vetted Early Years Practitioners',
          'Automated timesheets & invoice generation',
          'Standard weekday staffing support',
        ],
      ),
      const Plan(
        id: 'premium',
        name: 'Premium Subscription',
        description: 'Designed for high-capacity nurseries and multi-branch early years groups',
        pricePence: 29900,
        billingInterval: 'month',
        bookingAllowance: 0,
        trialDays: 0,
        active: true,
        benefits: [
          'Everything in Standard plus Priority Cover dispatch',
          'Dedicated Account Manager & Emergency WhatsApp cover',
          'Multi-branch / location administration included',
          'Fastest practitioner matching algorithms',
        ],
      ),
      const Plan(
        id: 'payg',
        name: 'Pay As You Go',
        description: 'Zero recurring monthly commitment; pay per booking',
        pricePence: 999,
        billingInterval: 'per_booking',
        bookingAllowance: 0,
        trialDays: 0,
        active: true,
        benefits: [
          'No monthly subscription fee',
          '£9.99 flat booking fee per confirmed shift',
          'Standard timesheet and invoicing included',
        ],
      ),
      const Plan(
        id: 'trial',
        name: '14-Day Free Trial',
        description: 'Free onboarding trial upon verified nursery registration',
        pricePence: 0,
        billingInterval: 'none',
        bookingAllowance: 0,
        trialDays: 14,
        active: true,
        benefits: [
          'Full platform access for 14 calendar days',
          'Post shifts and browse practitioners with zero subscription fee',
          'Staffing hours worked settled separately at standard rate',
        ],
      ),
    ];

    return Column(
      children: defaultSeedPlans
          .map((p) => _PlanCard(
                plan: p,
                isNursery: isNursery,
                isCurrent: p.id == currentPlanId,
                busy: busyPlanId == p.id,
                onSelect: () => onSelect(p.id),
              ))
          .toList(),
    );
  }
}

class _PractitionerBenefitRow extends StatelessWidget {
  const _PractitionerBenefitRow({
    required this.icon,
    required this.title,
    required this.desc,
  });

  final IconData icon;
  final String title;
  final String desc;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: const Color(0xFF059669), size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF64748B),
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
