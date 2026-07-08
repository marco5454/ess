import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/callings_providers.dart';

/// Free-text organization field with autocomplete over existing values.
///
/// Wraps a plain [TextFormField] with Flutter's built-in [RawAutocomplete]
/// so a user typing "Prim..." sees "Primary" as a suggestion and picks it
/// instead of inventing a slightly different spelling. Keeping organization
/// strings consistent is what makes the Summary's group-by-organization view
/// readable — one drifted "Elders quorum" splits a section in two.
///
/// The widget is a drop-in replacement for the previous `TextFormField`:
/// callers keep supplying the same [TextEditingController] and read
/// `controller.text` on save just like before. The user is *not* forced to
/// pick a suggestion — arbitrary text is still accepted, so entirely new
/// organizations can still be created.
///
/// Suggestions are sourced from [distinctOrganizationsProvider]. While that
/// provider is loading or errors out, the field silently degrades to a plain
/// text field so form entry is never blocked.
class OrganizationField extends ConsumerStatefulWidget {
  const OrganizationField({
    super.key,
    required this.controller,
    this.labelText = 'Organization',
    this.hintText = 'e.g. Elders Quorum, Primary, Ward',
  });

  final TextEditingController controller;
  final String labelText;
  final String hintText;

  @override
  ConsumerState<OrganizationField> createState() => _OrganizationFieldState();
}

class _OrganizationFieldState extends ConsumerState<OrganizationField> {
  /// Max suggestions to render in the overlay. Wards rarely need many
  /// distinct orgs, but capping keeps the overlay from ever becoming a
  /// scrolling monster if the data is dirty.
  static const _maxSuggestions = 8;

  /// Own the focus node so it survives rebuilds and gets disposed cleanly.
  /// Reusing the same node across rebuilds is also what lets the trailing
  /// dropdown-icon "re-open suggestions" trick work reliably.
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final orgs = ref.watch(distinctOrganizationsProvider).value ?? const <String>[];

    return RawAutocomplete<String>(
      textEditingController: widget.controller,
      focusNode: _focusNode,
      // We use `RawAutocomplete` (instead of the higher-level `Autocomplete`)
      // so we can pass our *own* controller — the parent screens rely on
      // reading `_organization.text` at save time. Flutter's canonical
      // `Autocomplete` widget owns its controller and doesn't expose it.
      optionsBuilder: (TextEditingValue value) {
        if (orgs.isEmpty) return const Iterable<String>.empty();
        final query = value.text.trim().toLowerCase();
        // Empty query: show everything (helpful when the user just taps in
        // to see what already exists in the ward).
        final matches = query.isEmpty
            ? orgs
            : orgs.where((o) => o.toLowerCase().contains(query)).toList();
        // Hide the overlay when the only "match" is the exact value the user
        // has already typed — no point suggesting what's already there.
        if (matches.length == 1 &&
            matches.first.toLowerCase() == query &&
            query.isNotEmpty) {
          return const Iterable<String>.empty();
        }
        return matches.take(_maxSuggestions);
      },
      fieldViewBuilder:
          (context, controller, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: controller,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.next,
          onFieldSubmitted: (_) => onFieldSubmitted(),
          decoration: InputDecoration(
            labelText: widget.labelText,
            hintText: widget.hintText,
            // Trailing icon hints at the suggestion affordance without
            // shouting. Tapping it re-opens the overlay by re-focusing.
            suffixIcon: orgs.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.arrow_drop_down),
                    tooltip: 'Show suggestions',
                    onPressed: () {
                      if (focusNode.hasFocus) {
                        // Nudge the options builder to re-run so the
                        // dropdown appears even when text hasn't changed.
                        controller.value = TextEditingValue(
                          text: controller.text,
                          selection: TextSelection.collapsed(
                              offset: controller.text.length),
                        );
                      } else {
                        focusNode.requestFocus();
                      }
                    },
                  ),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final query = widget.controller.text.trim();
        final hasExactMatch = options.any(
          (o) => o.toLowerCase() == query.toLowerCase(),
        );
        final showNewHint = query.isNotEmpty && !hasExactMatch;

        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 480),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final option in options)
                    _SuggestionTile(
                      label: option,
                      query: query,
                      onTap: () {
                        onSelected(option);
                        // Provide light tactile feedback on selection so a
                        // pick feels different from a keystroke.
                        HapticFeedback.selectionClick();
                      },
                    ),
                  if (showNewHint)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                      child: Text(
                        'Press enter to use "$query" as a new organization',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One row in the suggestion overlay. Bolds the substring the user has
/// already typed so it's obvious which suggestion continues their input.
class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.label,
    required this.query,
    required this.onTap,
  });

  final String label;
  final String query;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Row(
          children: [
            Icon(
              Icons.corporate_fare,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _highlighted(theme, label, query),
            ),
          ],
        ),
      ),
    );
  }

  /// Renders [label] with the case-insensitive [query] substring bolded.
  Widget _highlighted(ThemeData theme, String label, String query) {
    if (query.isEmpty) {
      return Text(label, style: theme.textTheme.bodyMedium);
    }
    final lowerLabel = label.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final start = lowerLabel.indexOf(lowerQuery);
    if (start < 0) {
      return Text(label, style: theme.textTheme.bodyMedium);
    }
    final end = start + query.length;
    final base = theme.textTheme.bodyMedium;
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: label.substring(0, start)),
          TextSpan(
            text: label.substring(start, end),
            style: base?.copyWith(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: label.substring(end)),
        ],
      ),
    );
  }
}
