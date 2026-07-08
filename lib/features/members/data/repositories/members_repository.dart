// ignore_for_file: prefer_initializing_formals
//
// Rationale: the private fields are named with underscores; using
// initializing formals here would force callers to pass `_dao:` /
// `_outbox:` because the parameter name would leak. Preferring the explicit
// assignment keeps the public constructor names clean.

import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../../../../core/sync/outbox_dao.dart';
import '../local/members_dao.dart';
import '../../domain/entities/member.dart';

/// Data-layer facade over ward members.
///
/// **Local-first**: every mutation writes to the local Drift DB immediately
/// (so the UI updates without waiting for the network), then enqueues an
/// outbox entry that the sync worker will push to Supabase. When the
/// realtime echo arrives it authoritative-overwrites the local row via the
/// DAO's `upsertFromServerMap`.
///
/// Reads come from the local Drift database (populated by the initial seed
/// and the realtime subscription).
class MembersRepository {
  MembersRepository({
    required MembersDao dao,
    required OutboxDao outbox,
    required Future<void> Function() kickDrain,
    Uuid? uuid,
  })  : _dao = dao,
        _outbox = outbox,
        _kickDrain = kickDrain,
        _uuid = uuid ?? const Uuid();

  final MembersDao _dao;
  final OutboxDao _outbox;
  final Future<void> Function() _kickDrain;
  final Uuid _uuid;

  /// Snapshot of members from the local DB. [activeOnly] defaults to true.
  Future<List<Member>> listMembers({bool activeOnly = true}) async {
    return _dao.watchAll(activeOnly: activeOnly).first;
  }

  /// One-shot fetch for a single member by id. Throws if not found.
  Future<Member> getMember(String id) async {
    final row = await _dao.getById(id);
    if (row == null) {
      throw StateError('Member $id not found in local database');
    }
    return row;
  }

  /// Live stream of all members (active + archived), alphabetized. Callers
  /// filter client-side (see `activeMembersProvider`).
  Stream<List<Member>> watchMembers() {
    return _dao.watchAll(activeOnly: false);
  }

  /// Create a new member locally and enqueue the insert for the server.
  ///
  /// The generated id is a client-side uuid v4 and is used both locally and
  /// server-side, so the row survives round-trips without renaming. The
  /// returned [Member] is the local record; timestamps may be superseded
  /// when the server echo arrives.
  Future<Member> addMember(NewMember input) async {
    final now = DateTime.now().toUtc();
    final id = _uuid.v4();
    final member = Member(
      id: id,
      firstName: input.firstName.trim(),
      lastName: input.lastName.trim(),
      preferredName: _blankToNull(input.preferredName),
      phone: _blankToNull(input.phone),
      email: _blankToNull(input.email),
      notes: _blankToNull(input.notes),
      dateOfBirth: input.dateOfBirth,
      sex: _blankToNull(input.sex),
      priesthoodOffice: _blankToNull(input.priesthoodOffice),
      isActive: true,
      createdAt: now,
      updatedAt: now,
    );

    await _dao.insertLocal(member);

    // Server payload mirrors what NewMember.toInsert produced pre-Phase-3,
    // plus the client-authored `id`, `created_at`, `updated_at` so the
    // server row matches ours.
    final payload = <String, dynamic>{
      'id': id,
      ...input.toInsert(),
      'created_at': now.toIso8601String(),
      'updated_at': now.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.member,
      entityId: id,
      operation: OutboxOp.insert,
      payloadJson: jsonEncode(payload),
    );
    _fireDrain();
    return member;
  }

  /// Apply an update locally and enqueue it for the server.
  Future<Member> updateMember(String id, MemberUpdate update) async {
    final now = DateTime.now().toUtc();
    final member = Member(
      id: id,
      firstName: update.firstName.trim(),
      lastName: update.lastName.trim(),
      preferredName: _blankToNull(update.preferredName),
      phone: _blankToNull(update.phone),
      email: _blankToNull(update.email),
      notes: _blankToNull(update.notes),
      dateOfBirth: update.dateOfBirth,
      sex: _blankToNull(update.sex),
      priesthoodOffice: _blankToNull(update.priesthoodOffice),
      isActive: update.isActive,
      // Preserve the existing createdAt if we can find it; else `now` is
      // a reasonable placeholder that the server echo will correct.
      createdAt: (await _dao.getById(id))?.createdAt ?? now,
      updatedAt: now,
    );

    await _dao.updateLocal(member);

    final payload = <String, dynamic>{
      ...update.toUpdate(),
      'updated_at': now.toIso8601String(),
    };
    await _outbox.enqueue(
      opId: _uuid.v4(),
      entityType: OutboxEntityType.member,
      entityId: id,
      operation: OutboxOp.update,
      payloadJson: jsonEncode(payload),
    );
    _fireDrain();
    return member;
  }

  void _fireDrain() {
    // Fire-and-forget: any errors are captured on the outbox entry itself.
    // ignore: discarded_futures
    _kickDrain();
  }

  static String? _blankToNull(String? value) {
    if (value == null) return null;
    final t = value.trim();
    return t.isEmpty ? null : t;
  }
}
