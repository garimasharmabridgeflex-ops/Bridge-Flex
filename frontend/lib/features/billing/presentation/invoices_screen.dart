import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_spacing.dart';
import '../domain/billing_models.dart';

final nurseryInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((ref) {
  return ref.watch(billingRepositoryProvider).listInvoices();
});

class InvoicesScreen extends ConsumerWidget {
  const InvoicesScreen({super.key});

  void _showInvoiceDetail(BuildContext context, Invoice inv) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(inv.invoiceNumber, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Issued: ${inv.issueDate.day}/${inv.issueDate.month}/${inv.issueDate.year} · Due: ${inv.dueDate.day}/${inv.dueDate.month}/${inv.dueDate.year}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: AppSpacing.md),
            const Text('Line Items', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: AppSpacing.sm),
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  for (final item in inv.lineItems)
                    ListTile(
                      dense: true,
                      title: Text(item.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                      trailing: Text(item.totalFormatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Subtotal (ex-VAT):', style: TextStyle(fontSize: 13)),
                Text(inv.subtotalFormatted, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              ],
            ),
            if (inv.vatPence > 0) ...[
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('VAT (${(inv.vatRate * 100).round()}%):', style: const TextStyle(fontSize: 13)),
                  Text(inv.vatFormatted, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                ],
              ),
            ],
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Due:', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text(inv.totalFormatted, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: AppColors.teal)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            if (inv.isPaid) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle_rounded, color: AppColors.teal, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Paid on ${inv.paidAt?.day}/${inv.paidAt?.month}/${inv.paidAt?.year} · Ref: ${inv.paymentReference}',
                        style: const TextStyle(color: AppColors.teal, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Bank Transfer Settlement Instructions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    const SizedBox(height: 6),
                    const Text('Beneficiary: K Flex Ltd\nSort Code: 20-40-60\nAccount No: 88201945', style: TextStyle(fontSize: 12)),
                    const SizedBox(height: 4),
                    Text('Payment Reference: ${inv.invoiceNumber}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.teal)),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Color _statusColor(Invoice inv) {
    if (inv.isPaid) return AppColors.teal;
    if (inv.isOverdue) return AppColors.coral;
    return AppColors.amber;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invoicesAsync = ref.watch(nurseryInvoicesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invoices & Billing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(nurseryInvoicesProvider),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(nurseryInvoicesProvider),
        child: invoicesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('Error loading invoices: $e')),
          data: (invoices) {
            if (invoices.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Text(
                      'No invoices yet. Weekly invoices are generated automatically for approved staffing hours.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.md),
              itemCount: invoices.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (ctx, idx) {
                final inv = invoices[idx];
                final color = _statusColor(inv);

                return Card(
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_rounded, color: color),
                    title: Text(inv.invoiceNumber, style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text('Issued ${inv.issueDate.day}/${inv.issueDate.month}/${inv.issueDate.year} · Due ${inv.dueDate.day}/${inv.dueDate.month}'),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(inv.totalFormatted, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            inv.status.toUpperCase(),
                            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                    onTap: () => _showInvoiceDetail(context, inv),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
