import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../../shared/widgets/primary_button.dart';
import '../domain/branch.dart';

final branchesProvider = FutureProvider.autoDispose<List<Branch>>((ref) async {
  return ref.watch(profileRepositoryProvider).listBranches();
});

class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  Future<void> _showAddBranchDialog([Branch? existing]) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final addrCtrl = TextEditingController(text: existing?.address ?? '');
    final postCtrl = TextEditingController(text: existing?.postcode ?? '');
    final cityCtrl = TextEditingController(text: existing?.city ?? '');
    final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
    final contactCtrl = TextEditingController(text: existing?.contactPerson ?? '');
    final ofstedCtrl = TextEditingController(text: existing?.ofstedRegNumber ?? '');
    bool isPrimary = existing?.isPrimary ?? false;
    bool saving = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.lg,
            right: AppSpacing.lg,
            top: AppSpacing.lg,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  existing == null ? 'Add Location / Branch' : 'Edit Location',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(label: 'Branch name', controller: nameCtrl),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(label: 'Address', controller: addrCtrl),
                const SizedBox(height: AppSpacing.sm),
                Row(
                  children: [
                    Expanded(child: AppTextField(label: 'Postcode', controller: postCtrl)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: AppTextField(label: 'City', controller: cityCtrl)),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(label: 'Phone number (optional)', controller: phoneCtrl),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(label: 'Contact person (optional)', controller: contactCtrl),
                const SizedBox(height: AppSpacing.sm),
                AppTextField(label: 'Ofsted Reg number (optional)', controller: ofstedCtrl),
                const SizedBox(height: AppSpacing.sm),
                CheckboxListTile(
                  title: const Text('Set as primary setting'),
                  value: isPrimary,
                  onChanged: (v) => setModalState(() => isPrimary = v ?? false),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: AppSpacing.md),
                PrimaryButton(
                  label: existing == null ? 'Create Branch' : 'Save Changes',
                  loading: saving,
                  onPressed: () async {
                    if (nameCtrl.text.trim().isEmpty || addrCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Branch name and address are required')),
                      );
                      return;
                    }
                    setModalState(() => saving = true);
                    try {
                      final branch = Branch(
                        id: existing?.id ?? '',
                        nurseryId: '',
                        name: nameCtrl.text.trim(),
                        address: addrCtrl.text.trim(),
                        postcode: postCtrl.text.trim(),
                        city: cityCtrl.text.trim(),
                        phone: phoneCtrl.text.trim(),
                        contactPerson: contactCtrl.text.trim(),
                        ofstedRegNumber: ofstedCtrl.text.trim(),
                        isPrimary: isPrimary,
                      );
                      if (existing == null) {
                        await ref.read(profileRepositoryProvider).createBranch(branch);
                      } else {
                        await ref.read(profileRepositoryProvider).updateBranch(branch);
                      }
                      ref.invalidate(branchesProvider);
                      if (ctx.mounted) Navigator.pop(ctx);
                    } on ApiException catch (e) {
                      if (ctx.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    } finally {
                      if (ctx.mounted) setModalState(() => saving = false);
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(branchesProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Branches & Locations'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddBranchDialog(),
        icon: const Icon(Icons.add_location_alt_rounded),
        label: const Text('Add Branch'),
      ),
      body: branchesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error loading branches: $e')),
        data: (branches) {
          if (branches.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.apartment_rounded, size: 64, color: scheme.onSurfaceVariant),
                  const SizedBox(height: AppSpacing.md),
                  const Text('No branches added yet'),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton.icon(
                    onPressed: () => _showAddBranchDialog(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Add your first location'),
                  ),
                ],
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(AppSpacing.md),
            itemCount: branches.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final branch = branches[index];
              return Card(
                elevation: 0,
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  side: BorderSide(
                    color: branch.isPrimary ? AppColors.indigo : scheme.outlineVariant,
                    width: branch.isPrimary ? 1.5 : 1.0,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            branch.isPrimary ? Icons.star_rounded : Icons.location_on_outlined,
                            color: branch.isPrimary ? AppColors.amber : AppColors.indigo,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              branch.name,
                              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                            ),
                          ),
                          if (branch.isPrimary)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.indigo.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: const Text(
                                'Primary',
                                style: TextStyle(
                                  color: AppColors.indigo,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text('${branch.address}, ${branch.postcode} ${branch.city}'),
                      if (branch.phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Phone: ${branch.phone}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      ],
                      if (branch.contactPerson.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text('Contact: ${branch.contactPerson}', style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton.icon(
                            onPressed: () => _showAddBranchDialog(branch),
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            label: const Text('Edit'),
                          ),
                          if (!branch.isPrimary)
                            TextButton.icon(
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Delete Branch'),
                                    content: Text('Are you sure you want to delete ${branch.name}?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  try {
                                    await ref.read(profileRepositoryProvider).deleteBranch(branch.id);
                                    ref.invalidate(branchesProvider);
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
                                    }
                                  }
                                }
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Colors.red),
                              label: const Text('Delete', style: TextStyle(color: Colors.red)),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
