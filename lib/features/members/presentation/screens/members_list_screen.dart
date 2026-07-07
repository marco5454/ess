import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/router/app_router.dart';
import '../../domain/entities/member.dart';
import '../providers/members_providers.dart';

/// Phase 2 members list.
///
/// Shows all active members, alphabetical, with a search field that filters
/// by first / last / preferred name as the user types. FAB navigates to the
/// add-member form. Sign-out lives in the app bar so we don't need a separate
/// home screen in Phase 2.
class MembersListScreen extends ConsumerStatefulWidget {
  const MembersListScreen({super.key});

  @override
  ConsumerState<MembersListScreen> createState() => _MembersListScreenState();
}

class _MembersListScreenState extends ConsumerState<MembersListScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() => _query = value.trim().toLowerCase());
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  /// Case-insensitive contains-match against first, last, and preferred name.
  List<Member> _applyFilter(List<Member> members) {
    if (_query.isEmpty) return members;
    return members.where((m) {
      final first = m.firstName.toLowerCase();
      final last = m.lastName.toLowerCase();
      final preferred = m.preferredName?.toLowerCase() ?? '';
      return first.contains(_query) ||
          last.contains(_query) ||
          preferred.contains(_query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final membersAsync = ref.watch(activeMembersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Members'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => supabase.auth.signOut(),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search members',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Clear search',
                        onPressed: _clearSearch,
                      ),
                isDense: true,
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async =>
            ref.invalidate(allMembersStreamProvider),
        child: membersAsync.when(
          data: (members) {
            if (members.isEmpty) {
              return ListView(
                // ListView so RefreshIndicator has something scrollable.
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No members yet.\nTap + to add one.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            final filtered = _applyFilter(members);
            if (filtered.isEmpty) {
              return ListView(
                children: [
                  const SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'No members match "${_searchController.text}".',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              );
            }
            return ListView.separated(
              itemCount: filtered.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final m = filtered[index];
                final subtitleParts = <String>[
                  if (m.priesthoodOffice != null &&
                      m.priesthoodOffice!.isNotEmpty)
                    m.priesthoodOffice!,
                  if (m.email != null && m.email!.isNotEmpty) m.email!,
                ];
                return ListTile(
                  title: Text(m.sortName),
                  subtitle: subtitleParts.isEmpty
                      ? null
                      : Text(subtitleParts.join(' • ')),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push(AppRoutes.memberDetail(m.id)),
                );
              },
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => ListView(
            children: [
              const SizedBox(height: 120),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Failed to load members:\n$error',
                      textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add member',
        onPressed: () => context.push(AppRoutes.memberAdd),
        child: const Icon(Icons.person_add),
      ),
    );
  }
}
