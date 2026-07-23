import 'package:flutter/material.dart';

import 'chip_multi_select.dart';

/// Single-select chips over a curated list, plus an "Other" chip that
/// reveals a free-text field — so a closed preset list never traps a value
/// that doesn't fit one of the curated options.
class ChipOrOtherSelect extends StatefulWidget {
  const ChipOrOtherSelect({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
    this.otherHint = 'Type your own…',
  });

  final List<ChipOption> options;
  final String value;
  final ValueChanged<String> onChanged;
  final String otherHint;

  @override
  State<ChipOrOtherSelect> createState() => _ChipOrOtherSelectState();
}

class _ChipOrOtherSelectState extends State<ChipOrOtherSelect> {
  late final _otherController = TextEditingController(text: _valueIsCustom ? widget.value : '');

  // Sticky once the user explicitly taps "Other", so the text field doesn't
  // disappear the instant they clear it back to empty while still typing.
  bool _otherTapped = false;

  bool get _valueIsCustom => widget.value.isNotEmpty && widget.options.every((o) => o.value != widget.value);

  bool get _isOther => _otherTapped || _valueIsCustom;

  @override
  Widget build(BuildContext context) {
    final isOther = _isOther;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...widget.options.map((opt) {
              return ChoiceChip(
                label: Text(opt.label),
                selected: !isOther && widget.value == opt.value,
                onSelected: (_) {
                  setState(() => _otherTapped = false);
                  widget.onChanged(opt.value);
                },
              );
            }),
            ChoiceChip(
              label: const Text('Other'),
              selected: isOther,
              onSelected: (_) {
                setState(() => _otherTapped = true);
                widget.onChanged(_otherController.text);
              },
            ),
          ],
        ),
        if (isOther) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _otherController,
            decoration: InputDecoration(hintText: widget.otherHint, isDense: true),
            onChanged: widget.onChanged,
          ),
        ],
      ],
    );
  }

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }
}
