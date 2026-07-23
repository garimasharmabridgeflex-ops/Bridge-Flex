import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app/theme.dart';

// ─── Country data ─────────────────────────────────────────────────────────────

class _Country {
  const _Country(this.name, this.flag, this.dialCode);
  final String name;
  final String flag;
  final String dialCode;
}

/// A curated list covering the most common markets. Sorted by name.
const List<_Country> _countries = [
  _Country('Afghanistan', '🇦🇫', '+93'),
  _Country('Albania', '🇦🇱', '+355'),
  _Country('Algeria', '🇩🇿', '+213'),
  _Country('Argentina', '🇦🇷', '+54'),
  _Country('Australia', '🇦🇺', '+61'),
  _Country('Austria', '🇦🇹', '+43'),
  _Country('Bangladesh', '🇧🇩', '+880'),
  _Country('Belgium', '🇧🇪', '+32'),
  _Country('Brazil', '🇧🇷', '+55'),
  _Country('Canada', '🇨🇦', '+1'),
  _Country('Chile', '🇨🇱', '+56'),
  _Country('China', '🇨🇳', '+86'),
  _Country('Colombia', '🇨🇴', '+57'),
  _Country('Croatia', '🇭🇷', '+385'),
  _Country('Czech Republic', '🇨🇿', '+420'),
  _Country('Denmark', '🇩🇰', '+45'),
  _Country('Egypt', '🇪🇬', '+20'),
  _Country('Ethiopia', '🇪🇹', '+251'),
  _Country('Finland', '🇫🇮', '+358'),
  _Country('France', '🇫🇷', '+33'),
  _Country('Germany', '🇩🇪', '+49'),
  _Country('Ghana', '🇬🇭', '+233'),
  _Country('Greece', '🇬🇷', '+30'),
  _Country('Hungary', '🇭🇺', '+36'),
  _Country('India', '🇮🇳', '+91'),
  _Country('Indonesia', '🇮🇩', '+62'),
  _Country('Iran', '🇮🇷', '+98'),
  _Country('Iraq', '🇮🇶', '+964'),
  _Country('Ireland', '🇮🇪', '+353'),
  _Country('Israel', '🇮🇱', '+972'),
  _Country('Italy', '🇮🇹', '+39'),
  _Country('Japan', '🇯🇵', '+81'),
  _Country('Jordan', '🇯🇴', '+962'),
  _Country('Kenya', '🇰🇪', '+254'),
  _Country('Kuwait', '🇰🇼', '+965'),
  _Country('Lebanon', '🇱🇧', '+961'),
  _Country('Malaysia', '🇲🇾', '+60'),
  _Country('Mexico', '🇲🇽', '+52'),
  _Country('Morocco', '🇲🇦', '+212'),
  _Country('Netherlands', '🇳🇱', '+31'),
  _Country('New Zealand', '🇳🇿', '+64'),
  _Country('Nigeria', '🇳🇬', '+234'),
  _Country('Norway', '🇳🇴', '+47'),
  _Country('Pakistan', '🇵🇰', '+92'),
  _Country('Philippines', '🇵🇭', '+63'),
  _Country('Poland', '🇵🇱', '+48'),
  _Country('Portugal', '🇵🇹', '+351'),
  _Country('Qatar', '🇶🇦', '+974'),
  _Country('Romania', '🇷🇴', '+40'),
  _Country('Russia', '🇷🇺', '+7'),
  _Country('Saudi Arabia', '🇸🇦', '+966'),
  _Country('Singapore', '🇸🇬', '+65'),
  _Country('South Africa', '🇿🇦', '+27'),
  _Country('South Korea', '🇰🇷', '+82'),
  _Country('Spain', '🇪🇸', '+34'),
  _Country('Sri Lanka', '🇱🇰', '+94'),
  _Country('Sweden', '🇸🇪', '+46'),
  _Country('Switzerland', '🇨🇭', '+41'),
  _Country('Tanzania', '🇹🇿', '+255'),
  _Country('Thailand', '🇹🇭', '+66'),
  _Country('Turkey', '🇹🇷', '+90'),
  _Country('UAE', '🇦🇪', '+971'),
  _Country('Uganda', '🇺🇬', '+256'),
  _Country('Ukraine', '🇺🇦', '+380'),
  _Country('United Kingdom', '🇬🇧', '+44'),
  _Country('United States', '🇺🇸', '+1'),
  _Country('Vietnam', '🇻🇳', '+84'),
  _Country('Zimbabwe', '🇿🇼', '+263'),
];

// ─── Widget ───────────────────────────────────────────────────────────────────

/// Phone input field with a tappable country-code prefix.
///
/// [controller] receives only the local number (digits, no dial code).
/// [onChanged] fires with the full E.164-style string: `"+44 7911 123456"`.
///
/// Pre-populate by setting [initialDialCode] (e.g. `"+44"`) and filling
/// [controller] with the local part.
class PhoneField extends StatefulWidget {
  const PhoneField({
    super.key,
    required this.controller,
    this.initialDialCode = '+44',
    this.onChanged,
    this.textInputAction = TextInputAction.done,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String initialDialCode;
  final ValueChanged<String>? onChanged;
  final TextInputAction textInputAction;
  final VoidCallback? onSubmitted;

  @override
  State<PhoneField> createState() => _PhoneFieldState();
}

class _PhoneFieldState extends State<PhoneField> {
  late _Country _selected;

  @override
  void initState() {
    super.initState();
    _selected = _countries.firstWhere(
      (c) => c.dialCode == widget.initialDialCode,
      orElse: () => _countries.firstWhere((c) => c.dialCode == '+44'),
    );
    widget.controller.addListener(_notify);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_notify);
    super.dispose();
  }

  void _notify() {
    widget.onChanged?.call('${_selected.dialCode} ${widget.controller.text.trim()}');
  }

  Future<void> _pickCountry() async {
    final result = await showModalBottomSheet<_Country>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryPickerSheet(selected: _selected),
    );
    if (result != null) {
      setState(() => _selected = result);
      _notify();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TextFormField(
      controller: widget.controller,
      keyboardType: TextInputType.phone,
      textInputAction: widget.textInputAction,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[\d\s\-()]'))],
      onFieldSubmitted: widget.onSubmitted != null ? (_) => widget.onSubmitted!() : null,
      decoration: InputDecoration(
        labelText: 'Phone number',
        prefixIcon: GestureDetector(
          onTap: _pickCountry,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border(
                right: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_selected.flag, style: const TextStyle(fontSize: 18)),
                const SizedBox(width: 4),
                Text(
                  _selected.dialCode,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.primary,
                      ),
                ),
                const SizedBox(width: 2),
                Icon(Icons.arrow_drop_down_rounded,
                    size: 18, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
      ),
    );
  }
}

// ─── Country picker bottom sheet ─────────────────────────────────────────────

class _CountryPickerSheet extends StatefulWidget {
  const _CountryPickerSheet({required this.selected});
  final _Country selected;

  @override
  State<_CountryPickerSheet> createState() => _CountryPickerSheetState();
}

class _CountryPickerSheetState extends State<_CountryPickerSheet> {
  final _searchCtrl = TextEditingController();
  List<_Country> _filtered = _countries;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _filter(String q) {
    final query = q.toLowerCase();
    setState(() {
      _filtered = query.isEmpty
          ? _countries
          : _countries
              .where((c) =>
                  c.name.toLowerCase().contains(query) ||
                  c.dialCode.contains(query))
              .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollCtrl) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(
                  'Select country code',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  controller: _searchCtrl,
                  autofocus: true,
                  onChanged: _filter,
                  decoration: InputDecoration(
                    hintText: 'Search country…',
                    prefixIcon:
                        const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _filter('');
                            },
                          )
                        : null,
                    contentPadding:
                        const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
                  ),
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  controller: scrollCtrl,
                  itemCount: _filtered.length,
                  itemBuilder: (_, i) {
                    final c = _filtered[i];
                    final isSelected = c.dialCode == widget.selected.dialCode &&
                        c.name == widget.selected.name;
                    return ListTile(
                      leading: Text(c.flag,
                          style: const TextStyle(fontSize: 22)),
                      title: Text(c.name),
                      trailing: Text(
                        c.dialCode,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      selected: isSelected,
                      selectedColor: scheme.primary,
                      onTap: () => Navigator.of(context).pop(c),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ─── Helper: split a stored phone string back into dial code + local ─────────

/// Returns `(dialCode, localNumber)` from a string like `"+44 7911 123456"`.
/// Falls back to `("+44", raw)` if the format isn't recognised.
(String dialCode, String localNumber) splitPhone(String raw) {
  if (raw.startsWith('+')) {
    for (final c in _countries) {
      if (raw.startsWith(c.dialCode)) {
        return (c.dialCode, raw.substring(c.dialCode.length).trim());
      }
    }
  }
  return ('+44', raw);
}
