import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/router/app_router.dart';
import '../providers/members_providers.dart';

/// Phase 2 members list.
///
/// Shows all active members, alphabetical. FAB navigates to the add-member
/// form. Sign-out lives in the app bar so we don't need a separate home
/// screen in Phase 2.
class MembersListScreen extends ConsumerWidget {
  const MembersListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(activeMembersProvider),
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
            return ListView.separated(
              itemCount: members.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final m = members[index];
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
