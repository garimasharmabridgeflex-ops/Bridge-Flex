import 'package:flutter/material.dart';

/// A text field with a filtered dropdown of suggestions from a fixed local
/// list — used for City/Nationality so typing "Lon" or "Brit" surfaces a
/// pickable match instead of requiring the whole word typed out. Free text
/// is still accepted (the list isn't exhaustive), the suggestions are just
/// a shortcut.
class LabeledAutocompleteField extends StatefulWidget {
  const LabeledAutocompleteField({
    super.key,
    required this.label,
    required this.controller,
    required this.options,
    this.prefixIcon,
    this.textInputAction,
  });

  final String label;
  final TextEditingController controller;
  final List<String> options;
  final IconData? prefixIcon;
  final TextInputAction? textInputAction;

  @override
  State<LabeledAutocompleteField> createState() => _LabeledAutocompleteFieldState();
}

class _LabeledAutocompleteFieldState extends State<LabeledAutocompleteField> {
  // RawAutocomplete asserts that focusNode and textEditingController are
  // either both provided or both omitted — since this field supplies its own
  // controller, it must also supply a matching (persistent, disposed here)
  // FocusNode rather than leaving RawAutocomplete to create one internally.
  final _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      optionsBuilder: (value) {
        if (value.text.trim().isEmpty) return const Iterable<String>.empty();
        final query = value.text.trim().toLowerCase();
        return widget.options.where((o) => o.toLowerCase().contains(query)).take(6);
      },
      fieldViewBuilder: (context, fieldController, focusNode, onSubmitted) {
        return TextFormField(
          controller: fieldController,
          focusNode: focusNode,
          textInputAction: widget.textInputAction,
          decoration: InputDecoration(
            labelText: widget.label,
            prefixIcon: widget.prefixIcon != null ? Icon(widget.prefixIcon, size: 20) : null,
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, matches) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 240, maxWidth: 420),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: matches.length,
                itemBuilder: (context, i) {
                  final option = matches.elementAt(i);
                  return ListTile(
                    dense: true,
                    title: Text(option),
                    onTap: () => onSelected(option),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}
