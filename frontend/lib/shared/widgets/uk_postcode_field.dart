import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

/// UK postcode field backed by postcodes.io's free, keyless autocomplete
/// endpoint — lets a nursery pick a real postcode from a partial (e.g.
/// "SW1A 1") instead of typing the whole thing correctly, and reports the
/// resolved postcode's district back so the caller can offer to prefill
/// the address.
class UkPostcodeField extends StatefulWidget {
  const UkPostcodeField({
    super.key,
    required this.controller,
    this.onResolved,
  });

  final TextEditingController controller;
  final ValueChanged<PostcodeDetails>? onResolved;

  @override
  State<UkPostcodeField> createState() => _UkPostcodeFieldState();
}

class PostcodeDetails {
  const PostcodeDetails({required this.postcode, required this.district, required this.region});
  final String postcode;
  final String district;
  final String region;
}

class _UkPostcodeFieldState extends State<UkPostcodeField> {
  Timer? _debounce;
  List<String> _suggestions = [];
  bool _loading = false;
  final _layerLink = LayerLink();
  final _fieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) _hideOverlay();
    });
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    _debounce?.cancel();
    _hideOverlay();
    _focusNode.dispose();
    super.dispose();
  }

  void _onChanged() {
    _debounce?.cancel();
    final query = widget.controller.text.trim();
    if (query.length < 2) {
      setState(() => _suggestions = []);
      _hideOverlay();
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () => _fetchSuggestions(query));
  }

  Future<void> _fetchSuggestions(String query) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.https('api.postcodes.io', '/postcodes/$query/autocomplete');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (!mounted) return;
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final result = (body['result'] as List?)?.cast<String>() ?? const [];
        setState(() => _suggestions = result);
        _showOverlay();
      }
    } catch (_) {
      // Best-effort — the field stays a plain, freely-editable text field
      // if postcodes.io is unreachable.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _select(String postcode) async {
    widget.controller.text = postcode;
    widget.controller.selection = TextSelection.collapsed(offset: postcode.length);
    _hideOverlay();
    setState(() => _suggestions = []);
    _focusNode.unfocus();
    if (widget.onResolved == null) return;
    try {
      final uri = Uri.https('api.postcodes.io', '/postcodes/$postcode');
      final res = await http.get(uri).timeout(const Duration(seconds: 5));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final result = body['result'] as Map<String, dynamic>?;
        if (result != null) {
          widget.onResolved!(PostcodeDetails(
            postcode: postcode,
            district: result['admin_district'] as String? ?? '',
            region: result['region'] as String? ?? '',
          ));
        }
      }
    } catch (_) {
      // Postcode itself is already filled in — the district-prefill is a
      // bonus, not required.
    }
  }

  void _showOverlay() {
    _hideOverlay();
    if (_suggestions.isEmpty) return;
    final fieldWidth =
        (_fieldKey.currentContext?.findRenderObject() as RenderBox?)?.size.width ?? 300.0;
    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: fieldWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 58),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, i) => ListTile(
                  dense: true,
                  leading: const Icon(Icons.place_outlined, size: 18),
                  title: Text(_suggestions[i]),
                  onTap: () => _select(_suggestions[i]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        key: _fieldKey,
        controller: widget.controller,
        focusNode: _focusNode,
        textCapitalization: TextCapitalization.characters,
        decoration: InputDecoration(
          labelText: 'Postcode',
          prefixIcon: const Icon(Icons.markunread_mailbox_outlined, size: 20),
          suffixIcon: _loading
              ? const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : null,
        ),
      ),
    );
  }
}
