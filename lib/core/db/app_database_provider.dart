import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app_database.dart';

/// Application-wide singleton handle to the local SQLite database.
///
/// The database is opened lazily on first read and closed automatically when
/// the containing [ProviderScope] is disposed. In practice that happens when
/// the whole app is torn down, which is when we want it — Drift holds a
/// long-lived native connection.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});
