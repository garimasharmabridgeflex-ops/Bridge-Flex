import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../../../core/widgets/primary_button.dart';
import '../domain/payroll_models.dart';

final practitionerEarningsProvider = FutureProvider.autoDispose<PractitionerEarningsSummary>((ref) {
  return ref.watch(payrollRepositoryProvider).getPractitionerEarnings();
});

final payrollProfileProvider = FutureProvider.autoDispose<PayrollProfile>((ref) {
  return ref.watch(payrollRepositoryProvider).getPayrollProfile();
});

class PractitionerEarningsScreen extends ConsumerStatefulWidget {
  const PractitionerEarningsScreen({super.key});

  @override
  ConsumerState<PractitionerEarningsScreen> createState() => _PractitionerEarningsScreenState();
}

class _PractitionerEarningsScreenState extends ConsumerState<PractitionerEarningsScreen> {
  void _editBankDetails(PayrollProfile profile) {
    final nameCtrl = TextEditingController(text: profile.bankAccountName);
    final accCtrl = TextEditingController();
    final sortCtrl = TextEditingController(text: profile.bankSortCode);
    final niCtrl = TextEditingController();
    bool busy = false;
    String? error;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.account_balance_rounded, color: AppColors.teal),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Bank & Payroll Details',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              const Text(
                'Enter your UK bank details and National Insurance number for direct PAYE wage payments:',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Account Holder Name',
                  hintText: 'e.g. Jane Doe',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: accCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Bank Account Number (8 digits)',
                  hintText: profile.bankAccountNumberMasked.isNotEmpty
                      ? 'Current: ${profile.bankAccountNumberMasked}'
                      : 'e.g. 12345678',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: sortCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Sort Code (6 digits)',
                  hintText: 'e.g. 20-40-60',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: niCtrl,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  labelText: 'National Insurance Number',
                  hintText: profile.nationalInsuranceNumberMasked.isNotEmpty
                      ? 'Current: ${profile.nationalInsuranceNumberMasked}'
                      : 'e.g. QQ 12 34 56 A',
                ),
              ),
              if (error != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(error!, style: const TextStyle(color: AppColors.coral, fontSize: 12)),
              ],
              const SizedBox(height: AppSpacing.lg),
              PrimaryButton(
                label: 'Save Bank Details',
                loading: busy,
                onPressed: () async {
                  setSheetState(() {
                    busy = true;
                    error = null;
                  });
                  try {
                    await ref.read(payrollRepositoryProvider).updatePayrollProfile(
                          bankAccountName: nameCtrl.text.trim(),
                          bankAccountNumber: accCtrl.text.trim().isNotEmpty ? accCtrl.text.trim() : null,
                          bankSortCode: sortCtrl.text.trim(),
                          nationalInsuranceNumber: niCtrl.text.trim().isNotEmpty ? niCtrl.text.trim() : null,
                        );
                    ref.invalidate(payrollProfileProvider);
                    if (ctx.mounted) Navigator.of(ctx).pop();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Payroll details saved successfully.'),
                          backgroundColor: AppColors.teal,
                        ),
                      );
                    }
                  } catch (e) {
                    setSheetState(() {
                      busy = false;
                      error = e.toString();
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final earningsAsync = ref.watch(practitionerEarningsProvider);
    final profileAsync = ref.watch(payrollProfileProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Earnings & Payslips'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () {
              ref.invalidate(practitionerEarningsProvider);
              ref.invalidate(payrollProfileProvider);
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(practitionerEarningsProvider);
          ref.invalidate(payrollProfileProvider);
        },
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Earnings Summary Card
              earningsAsync.when(
                loading: () => const Center(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(),
                  ),
                ),
                error: (e, _) => Card(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text('Error loading earnings: $e'),
                  ),
                ),
                data: (earnings) => Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: AppColors.teal.withValues(alpha: 0.2)),
                  ),
                  color: AppColors.teal.withValues(alpha: 0.05),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Total Gross Earnings',
                          style: TextStyle(fontSize: 14, color: Colors.grey, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          earnings.grossPayFormatted,
                          style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.teal),
                        ),
                        const SizedBox(height: 12),
                        const Divider(),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Completed Shifts', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 2),
                                Text('${earnings.totalCompletedShifts}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Approved Hours', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                const SizedBox(height: 2),
                                Text(earnings.billableHoursFormatted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                              ],
                            ),
                          ],
                        ),
                        if (earnings.eligibleForRolledUpHolidayPay) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Basic: ${earnings.basicPayFormatted}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                Text('Rolled-up Holiday (12.07%): ${earnings.holidayPayFormatted}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.teal)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Bank Details Card
              profileAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (profile) => Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: const [
                                Icon(Icons.account_balance_rounded, size: 20, color: AppColors.teal),
                                SizedBox(width: 8),
                                Text('Bank & Payroll Info', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              ],
                            ),
                            TextButton(
                              onPressed: () => _editBankDetails(profile),
                              child: const Text('Update'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Account Number:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            Text(
                              profile.bankAccountNumberMasked.isNotEmpty ? profile.bankAccountNumberMasked : 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Sort Code:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            Text(
                              profile.bankSortCode.isNotEmpty ? profile.bankSortCode : 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('National Insurance:', style: TextStyle(color: Colors.grey, fontSize: 13)),
                            Text(
                              profile.nationalInsuranceNumberMasked.isNotEmpty ? profile.nationalInsuranceNumberMasked : 'Not set',
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: AppSpacing.lg),

              // Payslips Section
              Row(
                children: const [
                  Icon(Icons.description_outlined, size: 20, color: AppColors.teal),
                  SizedBox(width: 8),
                  Text('Uploaded Payslips', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              earningsAsync.when(
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
                data: (earnings) {
                  if (earnings.payslips.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Center(
                        child: Text(
                          'No payslips uploaded yet. Payslips are added after each processed pay period.',
                          style: TextStyle(color: Colors.grey, fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: earnings.payslips.map((ps) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: const Icon(Icons.picture_as_pdf_rounded, color: AppColors.coral),
                          title: Text(ps.periodName.isNotEmpty ? ps.periodName : ps.fileName),
                          subtitle: Text('Added on ${ps.uploadedAt.day}/${ps.uploadedAt.month}/${ps.uploadedAt.year}'),
                          trailing: const Icon(Icons.download_rounded),
                          onTap: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Downloading ${ps.fileName}...')),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
