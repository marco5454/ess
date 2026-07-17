import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../members/domain/entities/member.dart';
import '../../../members/presentation/providers/members_providers.dart';

/// Compact tile-shaped field that opens a searchable member picker.
///
/// Returns `null` for "no member" (a ward-wide activity). Optional; the
/// user can leave it blank.
class MemberPickerField extends ConsumerWidget {
  const MemberPickerField({
    super.key,
    required this.selectedMemberId,
    required this.onChanged,
    this.label = 'Assigned member',
  });

  final String? selectedMemberId;
  final ValueChanged<String?> onChanged;
  final String label;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final membersAsync = ref.watch(activeMembersProvider);
    final selectedMember = membersAsync.maybeWhen(
      data: (list) {
        if (selectedMemberId == null) return null;
        for (final m in list) {
          if (m.id == selectedMemberId) return m;
        }
        return null;
      },
      orElse: () => null,
    );

    return InkWell(
      onTap: () => _openPicker(context, ref),
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: selectedMemberId == null
              ? const Icon(Icons.arrow_drop_down)
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear',
                  onPressed: () => onChanged(null),
                ),
        ),
        child: Text(
          selectedMember?.displayName ??
              (selectedMemberId == null
                  ? 'None (ward-wide)'
                  : 'Unknown member'),
          style: TextStyle(
            color: selectedMember == null
                ? Theme.of(context).hintColor
                : null,
          ),
        ),
      ),
    );
  }

  Future<void> _openPicker(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => const _MemberPickerSheet(),
    );
    if (result == null) return;
    onChanged(result.memberId);
  }
}

class _PickerResult {
  const _PickerResult(this.memberId);
  final String? memberId;
}

class _MemberPickerSheet extends ConsumerStatefulWidget {
  const _MemberPickerSheet();

  @override
  ConsumerState<_MemberPickerSheet> createState() =>
      _MemberPickerSheetState();
}

class _MemberPickerSheetState extends ConsumerState<_MemberPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(activeMembersProvider);
    final mediaQuery = MediaQuery.of(context);

    return SizedBox(
      height: mediaQuery.size.height * 0.7,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: mediaQuery.viewInsets.bottom,
          left: 16,
          right: 16,
          top: 8,
        ),
        child: Column(
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Search members',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
            const SizedBox(height: 8),
            // Ward-wide sentinel.
            ListTile(
              leading: const Icon(Icons.groups_outlined),
              title: const Text('None (ward-wide)'),
              onTap: () =>
                  Navigator.of(context).pop(const _PickerResult(null)),
            ),
            const Divider(height: 1),
            Expanded(
              child: membersAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('Failed to load: $e')),
                data: (members) {
                  final filtered = _filter(members);
                  if (filtered.isEmpty) {
                    return const Center(child: Text('No members match'));
                  }
                  return ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final m = filtered[i];
                      return ListTile(
                        title: Text(m.displayName),
                        subtitle: Text(m.sortName),
                        onTap: () => Navigator.of(context)
                            .pop(_PickerResult(m.id)),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Member> _filter(List<Member> members) {
    final sorted = [...members]
      ..sort((a, b) => a.sortName.compareTo(b.sortName));
    if (_query.isEmpty) return sorted;
    return sorted
        .where((m) =>
            m.displayName.toLowerCase().contains(_query) ||
            m.sortName.toLowerCase().contains(_query))
        .toList(growable: false);
  }
}
