import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../data/repositories/auth_repository.dart';

/// Provides the singleton [AuthRepository] wrapped over the app's
/// Supabase client. Split out from `auth_state_provider.dart` so the
/// session-tracking providers stay dependency-free.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(supabase);
});
