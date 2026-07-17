import 'package:flutter_test/flutter_test.dart';
import 'package:lds_bishopric_tracker/features/callings/domain/entities/calling.dart';
import 'package:lds_bishopric_tracker/features/callings/domain/entities/calling_event.dart';
import 'package:lds_bishopric_tracker/features/callings/domain/entities/calling_state.dart';
import 'package:lds_bishopric_tracker/features/callings/presentation/providers/callings_providers.dart';
import 'package:lds_bishopric_tracker/features/callings/presentation/screens/bishopric_agenda_screen.dart';
import 'package:lds_bishopric_tracker/features/members/domain/entities/member.dart';

Member _member({required String id, required String first, required String last}) {
  final now = DateTime(2026, 1, 1);
  return Member(
    id: id,
    firstName: first,
    lastName: last,
    isActive: true,
    createdAt: now,
    updatedAt: now,
  );
}

Calling _calling({
  required String id,
  required String memberId,
  required String title,
  String? org,
}) {
  final now = DateTime(2026, 1, 1);
  return Calling(
    id: id,
    memberId: memberId,
    title: title,
    organization: org,
    createdAt: now,
    updatedAt: now,
  );
}

CallingEvent _event({
  required String id,
  required String callingId,
  required CallingState state,
  required DateTime occurredAt,
}) {
  return CallingEvent(
    id: id,
    callingId: callingId,
    state: state,
    occurredAt: occurredAt,
    createdAt: occurredAt,
  );
}

CallingSummaryRow _row({
  required Member member,
  required Calling calling,
  required CallingEvent event,
}) {
  return CallingSummaryRow(calling: calling, member: member, latestEvent: event);
}

void main() {
  group('renderAgendaAsText', () {
    test('renders the header, all six section labels, and confidential banner',
        () {
      final agenda = BishopricAgenda(
        generatedAt: DateTime(2026, 7, 8),
        inServiceCount: 42,
        readyToSustain: const [],
        readyToSetApart: const [],
        awaitingResponse: const [],
        newSelections: const [],
        stalled: const [],
        recent: const [],
      );

      final text = renderAgendaAsText(agenda);

      expect(text, contains('Bishopric Agenda'));
      expect(text, contains('8 July 2026'));
      expect(text, contains('42 callings in service'));
      expect(text, contains('Confidential — Bishopric only'));
      expect(text, contains('READY TO SUSTAIN (0)'));
      expect(text, contains('READY TO SET APART (0)'));
      expect(text, contains('AWAITING RESPONSE (0)'));
      expect(text, contains('NEW SELECTIONS (0)'));
      expect(text, contains('STALLED 14+ DAYS (0)'));
      expect(text, contains('RECENT ACTIVITY (0)'));
    });

    test('renders a row with member name, calling title, organization, days',
        () {
      final member = _member(id: 'm1', first: 'John', last: 'Smith');
      final calling = _calling(
        id: 'c1',
        memberId: 'm1',
        title: 'Elders Quorum Second Counselor',
        org: 'Elders Quorum',
      );
      final event = _event(
        id: 'e1',
        callingId: 'c1',
        state: CallingState.accepted,
        occurredAt: DateTime.now().subtract(const Duration(days: 3)),
      );

      final agenda = BishopricAgenda(
        generatedAt: DateTime.now(),
        inServiceCount: 1,
        readyToSustain: [_row(member: member, calling: calling, event: event)],
        readyToSetApart: const [],
        awaitingResponse: const [],
        newSelections: const [],
        stalled: const [],
        recent: const [],
      );

      final text = renderAgendaAsText(agenda);

      expect(text, contains('READY TO SUSTAIN (1)'));
      expect(text, contains('John Smith'));
      expect(text, contains('Elders Quorum Second Counselor'));
      expect(text, contains('(Elders Quorum)'));
      expect(text, contains('3 days'));
    });

    test('empty sections render (none) placeholders so nothing is missing',
        () {
      final agenda = BishopricAgenda(
        generatedAt: DateTime(2026, 7, 8),
        inServiceCount: 0,
        readyToSustain: const [],
        readyToSetApart: const [],
        awaitingResponse: const [],
        newSelections: const [],
        stalled: const [],
        recent: const [],
      );

      final text = renderAgendaAsText(agenda);

      // Every section carries a "(none…)" line even when empty so the
      // shared plaintext keeps the same shape.
      expect(RegExp(r'\(none').allMatches(text).length, 6);
    });

    test('recent activity lines include member, calling title, new state, date',
        () {
      final member = _member(id: 'm1', first: 'Jane', last: 'Doe');
      final calling = _calling(
        id: 'c1',
        memberId: 'm1',
        title: 'Primary Teacher',
        org: 'Primary',
      );
      final event = _event(
        id: 'e1',
        callingId: 'c1',
        state: CallingState.setApart,
        occurredAt: DateTime(2026, 6, 15),
      );

      final agenda = BishopricAgenda(
        generatedAt: DateTime(2026, 7, 8),
        inServiceCount: 1,
        readyToSustain: const [],
        readyToSetApart: const [],
        awaitingResponse: const [],
        newSelections: const [],
        stalled: const [],
        recent: [
          RecentActivityRow(event: event, calling: calling, member: member),
        ],
      );

      final text = renderAgendaAsText(agenda);

      expect(text, contains('Jane Doe'));
      expect(text, contains('Primary Teacher → Set apart'));
      expect(text, contains('2026-06-15'));
    });

    test('meetingDate override replaces the header date', () {
      final agenda = BishopricAgenda(
        generatedAt: DateTime(2026, 7, 8),
        inServiceCount: 0,
        readyToSustain: const [],
        readyToSetApart: const [],
        awaitingResponse: const [],
        newSelections: const [],
        stalled: const [],
        recent: const [],
      );

      final text = renderAgendaAsText(
        agenda,
        meetingDate: DateTime(2026, 12, 25),
      );

      expect(text, contains('25 December 2026'));
      expect(text, isNot(contains('8 July 2026')));
    });

    test('rows with no linked member are skipped from sections', () {
      final member = _member(id: 'm1', first: 'John', last: 'Smith');
      final calling1 = _calling(
        id: 'c1',
        memberId: 'm1',
        title: 'Elders Quorum President',
      );
      final calling2 = _calling(
        id: 'c2',
        memberId: 'ghost',
        title: 'Orphaned Calling',
      );
      final event1 = _event(
        id: 'e1',
        callingId: 'c1',
        state: CallingState.accepted,
        occurredAt: DateTime.now().subtract(const Duration(days: 2)),
      );
      final event2 = _event(
        id: 'e2',
        callingId: 'c2',
        state: CallingState.accepted,
        occurredAt: DateTime.now().subtract(const Duration(days: 2)),
      );

      final agenda = BishopricAgenda(
        generatedAt: DateTime(2026, 7, 8),
        inServiceCount: 1,
        readyToSustain: [
          _row(member: member, calling: calling1, event: event1),
          // No member linked — should be filtered out.
          CallingSummaryRow(
            calling: calling2,
            member: null,
            latestEvent: event2,
          ),
        ],
        readyToSetApart: const [],
        awaitingResponse: const [],
        newSelections: const [],
        stalled: const [],
        recent: const [],
      );

      final text = renderAgendaAsText(agenda);

      // Section count reflects filtered rows only.
      expect(text, contains('READY TO SUSTAIN (1)'));
      expect(text, contains('John Smith'));
      expect(text, isNot(contains('Orphaned Calling')));
      expect(text, isNot(contains('Unknown member')));
    });

    test('recent-activity rows with no member are skipped', () {
      final member = _member(id: 'm1', first: 'Jane', last: 'Doe');
      final calling1 = _calling(
        id: 'c1',
        memberId: 'm1',
        title: 'Primary Teacher',
      );
      final calling2 = _calling(
        id: 'c2',
        memberId: 'ghost',
        title: 'Orphaned Calling',
      );
      final event1 = _event(
        id: 'e1',
        callingId: 'c1',
        state: CallingState.setApart,
        occurredAt: DateTime(2026, 6, 15),
      );
      final event2 = _event(
        id: 'e2',
        callingId: 'c2',
        state: CallingState.setApart,
        occurredAt: DateTime(2026, 6, 14),
      );

      final agenda = BishopricAgenda(
        generatedAt: DateTime(2026, 7, 8),
        inServiceCount: 1,
        readyToSustain: const [],
        readyToSetApart: const [],
        awaitingResponse: const [],
        newSelections: const [],
        stalled: const [],
        recent: [
          RecentActivityRow(event: event1, calling: calling1, member: member),
          RecentActivityRow(event: event2, calling: calling2, member: null),
        ],
      );

      final text = renderAgendaAsText(agenda);

      expect(text, contains('RECENT ACTIVITY (1)'));
      expect(text, contains('Jane Doe'));
      expect(text, isNot(contains('Unknown member')));
      expect(text, isNot(contains('Orphaned Calling')));
    });
  });
}
