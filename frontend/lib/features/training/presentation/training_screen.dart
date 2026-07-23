import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../shared/widgets/empty_state.dart';

/// Training tab — displays "Coming Soon" as specified.
class TrainingScreen extends StatelessWidget {
  const TrainingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Training')),
      body: const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: EmptyState(
          icon: Icons.school_outlined,
          title: 'Coming soon',
          subtitle: 'Training and CPD courses will land here in a future update.',
        ),
      ),
    );
  }
}
