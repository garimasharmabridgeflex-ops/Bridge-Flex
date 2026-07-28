import 'package:flutter/material.dart';

class ChipOption {
  const ChipOption(this.value, this.label, {this.icon});
  final String value;
  final String label;
  final IconData? icon;
}

/// Toggleable multi-select over a curated, fixed set of options — used for
/// facilities/skills/qualifications/availability/requirements chips across
/// the profile and shift-detail screens (full app spec profile-fields
/// request: "display as chips"). When [allowCustom] is set, an "+ Add
/// other" chip lets the user type and add a value outside the curated set —
/// a closed list should never trap someone whose real answer isn't listed.
class ChipMultiSelect extends StatefulWidget {
  const ChipMultiSelect({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.allowCustom = false,
  });

  final List<ChipOption> options;
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;
  final bool allowCustom;

  @override
  State<ChipMultiSelect> createState() => _ChipMultiSelectState();
}

class _ChipMultiSelectState extends State<ChipMultiSelect> {
  bool _adding = false;
  final _customController = TextEditingController();

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _toggle(String value, bool selectedNow) {
    final next = List<String>.from(widget.selected);
    if (selectedNow) {
      if (!next.contains(value)) next.add(value);
    } else {
      next.remove(value);
    }
    widget.onChanged(next);
  }

  void _addCustom() {
    final value = _customController.text.trim();
    if (value.isNotEmpty && !widget.selected.contains(value)) {
      widget.onChanged([...widget.selected, value]);
    }
    _customController.clear();
    setState(() => _adding = false);
  }

  @override
  Widget build(BuildContext context) {
    final customValues =
        widget.selected.where((v) => widget.options.every((o) => o.value != v)).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ...widget.options.map((opt) {
              final isSelected = widget.selected.contains(opt.value);
              return FilterChip(
                avatar: opt.icon != null ? Icon(opt.icon, size: 16) : null,
                label: Text(opt.label),
                selected: isSelected,
                onSelected: (sel) => _toggle(opt.value, sel),
              );
            }),
            ...customValues.map((v) {
              return Chip(
                label: Text(v),
                visualDensity: VisualDensity.compact,
                onDeleted: () => _toggle(v, false),
              );
            }),
            if (widget.allowCustom && !_adding)
              ActionChip(
                avatar: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Other'),
                onPressed: () => setState(() => _adding = true),
              ),
          ],
        ),
        if (widget.allowCustom && _adding) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _customController,
                  autofocus: true,
                  decoration: const InputDecoration(hintText: 'Type your own…', isDense: true),
                  onSubmitted: (_) => _addCustom(),
                ),
              ),
              IconButton(icon: const Icon(Icons.check_rounded), onPressed: _addCustom),
            ],
          ),
        ],
      ],
    );
  }
}

/// Read-only chip row for displaying a value list on profile/shift-detail
/// screens — looks up each raw stored value against [options] for its
/// label/icon, falling back to the raw value if it's a legacy/unknown entry.
class ChipDisplayRow extends StatelessWidget {
  const ChipDisplayRow({super.key, required this.values, required this.options});

  final List<String> values;
  final List<ChipOption> options;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: values.map((v) {
        final match = options.where((o) => o.value == v).firstOrNull;
        return Chip(
          avatar: match?.icon != null ? Icon(match!.icon, size: 16) : null,
          label: Text(match?.label ?? v),
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }
}
