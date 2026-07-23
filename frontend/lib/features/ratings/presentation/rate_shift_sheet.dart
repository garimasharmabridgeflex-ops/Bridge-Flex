import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/api/api_exception.dart';
import '../../../shared/widgets/primary_button.dart';

class RateShiftSheet extends ConsumerStatefulWidget {
  const RateShiftSheet({super.key, required this.shiftId, required this.rateeId});

  final String shiftId;
  final String rateeId;

  @override
  ConsumerState<RateShiftSheet> createState() => _RateShiftSheetState();
}

class _RateShiftSheetState extends ConsumerState<RateShiftSheet> {
  int _score = 5;
  final _comment = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _loading = true);
    try {
      await ref.read(ratingsRepositoryProvider).rate(
            shiftId: widget.shiftId,
            rateeId: widget.rateeId,
            score: _score,
            comment: _comment.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Thanks for your rating!')));
      }
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'How did it go?',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final filled = i < _score;
              return IconButton(
                onPressed: () => setState(() => _score = i + 1),
                icon: AnimatedScale(
                  scale: filled ? 1.15 : 1,
                  duration: const Duration(milliseconds: 150),
                  child: Icon(
                    filled ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: AppColors.amber,
                    size: 34,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _comment,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Add a comment (optional)'),
          ),
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(label: 'Submit rating', loading: _loading, onPressed: _submit),
        ],
      ),
    );
  }
}
