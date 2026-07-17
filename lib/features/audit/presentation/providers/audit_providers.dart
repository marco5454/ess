import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../admin/domain/entities/entity_history_entry.dart';
import '../../data/repositories/audit_repository.dart';

/// Provides the singleton [AuditRepository].
final auditRepositoryProvider = Provider<AuditRepository>((ref) {
  return AuditRepository(supabase);
});

/// Keying tuple for [entityHistoryProvider]. Two rebuilds for the same
/// (type, id) are deduplicated by Riverpod's family cache.
class EntityHistoryKey {
  const EntityHistoryKey({required this.entityType, required this.entityId});

  final String entityType;
  final String entityId;

  @override
  bool operator ==(Object other) =>
      other is EntityHistoryKey &&
      other.entityType == entityType &&
      other.entityId == entityId;

  @override
  int get hashCode => Object.hash(entityType, entityId);
}

/// Auto-disposing family provider for the first page of a record's redacted
/// history.
///
/// Currently returns a single page (first `pageSize` rows). If a screen
/// grows to need pagination, promote this to a Notifier-based provider
/// mirroring `AuditLogNotifier`.
final entityHistoryProvider =
    FutureProvider.autoDispose
        .family<List<EntityHistoryEntry>, EntityHistoryKey>((ref, key) async {
      final repo = ref.watch(auditRepositoryProvider);
      return repo.listForEntity(
        entityType: key.entityType,
        entityId: key.entityId,
        pageSize: 50,
      );
    });
