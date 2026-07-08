import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/app_database_provider.dart';
import 'outbox_dao.dart';

/// Riverpod handle for the outbox DAO. Depends on [appDatabaseProvider].
final outboxDaoProvider = Provider<OutboxDao>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return OutboxDao(db);
});
