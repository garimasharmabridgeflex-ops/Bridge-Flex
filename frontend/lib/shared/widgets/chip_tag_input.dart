import 'package:flutter/material.dart';

/// Free-text tag entry — type a value and submit to add a chip, tap a
/// chip's delete icon to remove it. Used for open-vocabulary lists (e.g.
/// languages spoken) where a curated [ChipMultiSelect] option set doesn't
/// fit.
class ChipTagInput extends StatefulWidget {
  const ChipTagInput({
    super.key,
    required this.values,
    required this.onChanged,
    this.hintText = 'Add and press enter',
  });

  final List<String> values;
  final ValueChanged<List<String>> onChanged;
  final String hintText;

  @override
  State<ChipTagInput> createState() => _ChipTagInputState();
}

class _ChipTagInputState extends State<ChipTagInput> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _add(String raw) {
    final value = raw.trim();
    if (value.isEmpty || widget.values.contains(value)) {
      _controller.clear();
      return;
    }
    widget.onChanged([...widget.values, value]);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.values.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: widget.values.map((v) {
                return Chip(
                  label: Text(v),
                  visualDensity: VisualDensity.compact,
                  onDeleted: () {
                    final next = List<String>.from(widget.values)..remove(v);
                    widget.onChanged(next);
                  },
                );
              }).toList(),
            ),
          ),
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            hintText: widget.hintText,
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.add_rounded),
              onPressed: () => _add(_controller.text),
            ),
          ),
          onSubmitted: _add,
        ),
      ],
    );
  }
}
