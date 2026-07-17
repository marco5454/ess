import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/admin_repository.dart';
import '../../domain/entities/audit_log_entry.dart';
import 'admin_providers.dart';

/// Read-only state for the paginated audit-log screen.
///
/// Backed by the `list_audit_log()` RPC, which uses keyset pagination on
/// `(occurred_at desc, id desc)`. We keep the accumulated entries in
/// memory; refresh clears the cursor and re-fetches the first page.
///
/// Filters ([actionLike], [actorId]) are part of the state so a rebuild
/// caused by filter change re-fetches with an empty cursor.
class AuditLogState {
  const AuditLogState({
    this.entries = const [],
    this.isLoading = false,
    this.hasMore = true,
    this.error,
    this.actionLike,
    this.actorId,
    this.sinceAt,
    this.untilAt,
  });

  final List<AuditLogEntry> entries;
  final bool isLoading;
  final bool hasMore;
  final Object? error;

  /// SQL LIKE pattern, e.g. `'member.%'`. Null = no filter.
  final String? actionLike;
  final String? actorId;

  /// Half-open date range on `occurred_at`. Both are optional; the server
  /// applies `>= sinceAt` and `< untilAt` when set.
  final DateTime? sinceAt;
  final DateTime? untilAt;

  AuditLogState copyWith({
    List<AuditLogEntry>? entries,
    bool? isLoading,
    bool? hasMore,
    Object? error,
    Object? actionLike = _unset,
    Object? actorId = _unset,
    Object? sinceAt = _unset,
    Object? untilAt = _unset,
  }) {
    return AuditLogState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      hasMore: hasMore ?? this.hasMore,
      error: error,
      actionLike: identical(actionLike, _unset)
          ? this.actionLike
          : actionLike as String?,
      actorId: identical(actorId, _unset) ? this.actorId : actorId as String?,
      sinceAt: identical(sinceAt, _unset)
          ? this.sinceAt
          : sinceAt as DateTime?,
      untilAt: identical(untilAt, _unset)
          ? this.untilAt
          : untilAt as DateTime?,
    );
  }

  static const _unset = Object();
}

/// Notifier controlling the audit-log screen state.
class AuditLogNotifier extends Notifier<AuditLogState> {
  static const _pageSize = 50;

  AdminRepository get _repo => ref.read(adminRepositoryProvider);

  @override
  AuditLogState build() {
    // Kick off the first page on subscribe.
    Future.microtask(_loadFirstPage);
    return const AuditLogState(isLoading: true);
  }

  Future<void> _loadFirstPage() async {
    try {
      final rows = await _repo.listAuditLog(
        pageSize: _pageSize,
        actionLike: state.actionLike,
        actorId: state.actorId,
        sinceAt: state.sinceAt,
        untilAt: state.untilAt,
      );
      state = state.copyWith(
        entries: rows,
        isLoading: false,
        hasMore: rows.length == _pageSize,
        error: null,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e, hasMore: false);
    }
  }

  /// Fetch the next page using the last entry as the keyset cursor. No-op
  /// if a load is already in flight or the last page has been reached.
  Future<void> loadMore() async {
    if (state.isLoading || !state.hasMore || state.entries.isEmpty) return;
    state = state.copyWith(isLoading: true, error: null);
    final last = state.entries.last;
    try {
      final rows = await _repo.listAuditLog(
        before: last.occurredAt,
        beforeId: last.id,
        pageSize: _pageSize,
        actionLike: state.actionLike,
        actorId: state.actorId,
        sinceAt: state.sinceAt,
        untilAt: state.untilAt,
      );
      state = state.copyWith(
        entries: [...state.entries, ...rows],
        isLoading: false,
        hasMore: rows.length == _pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e);
    }
  }

  /// Clear state and refetch the first page. Used by pull-to-refresh and
  /// after changing a filter.
  Future<void> refresh() async {
    state = AuditLogState(
      isLoading: true,
      actionLike: state.actionLike,
      actorId: state.actorId,
      sinceAt: state.sinceAt,
      untilAt: state.untilAt,
    );
    await _loadFirstPage();
  }

  /// Update the action filter (SQL LIKE pattern) and refresh. Pass null to
  /// clear.
  Future<void> setActionFilter(String? like) async {
    if (like == state.actionLike) return;
    state = AuditLogState(
      isLoading: true,
      actionLike: like,
      actorId: state.actorId,
      sinceAt: state.sinceAt,
      untilAt: state.untilAt,
    );
    await _loadFirstPage();
  }

  /// Update the half-open date range and refresh. Either bound may be null.
  Future<void> setDateRange({DateTime? sinceAt, DateTime? untilAt}) async {
    if (sinceAt == state.sinceAt && untilAt == state.untilAt) return;
    state = AuditLogState(
      isLoading: true,
      actionLike: state.actionLike,
      actorId: state.actorId,
      sinceAt: sinceAt,
      untilAt: untilAt,
    );
    await _loadFirstPage();
  }

  /// Clear the date range and refresh.
  Future<void> clearDateRange() => setDateRange();
}

final auditLogProvider = NotifierProvider<AuditLogNotifier, AuditLogState>(
  AuditLogNotifier.new,
);
