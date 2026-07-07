import 'package:flutter_test/flutter_test.dart';
import 'package:lds_bishopric_tracker/features/callings/domain/entities/calling_state.dart';

void main() {
  group('CallingState.wireName', () {
    test('setApart maps to snake_case set_apart', () {
      expect(CallingState.setApart.wireName, 'set_apart');
    });

    test('every other value is its lowercased name', () {
      for (final s in CallingState.values) {
        if (s == CallingState.setApart) continue;
        expect(s.wireName, s.name);
      }
    });

    test('round-trips via fromWire', () {
      for (final s in CallingState.values) {
        expect(CallingState.fromWire(s.wireName), s);
      }
    });
  });

  group('CallingState.fromWire', () {
    test('accepts the exact set of enum wire values', () {
      // Should not throw.
      for (final s in CallingState.values) {
        CallingState.fromWire(s.wireName);
      }
    });

    test('throws ArgumentError on an unknown value', () {
      expect(() => CallingState.fromWire('setApart'), throwsArgumentError);
      expect(() => CallingState.fromWire('unknown'), throwsArgumentError);
      expect(() => CallingState.fromWire(''), throwsArgumentError);
    });
  });

  group('CallingState.isTerminal', () {
    test('declined and released are terminal', () {
      expect(CallingState.declined.isTerminal, isTrue);
      expect(CallingState.released.isTerminal, isTrue);
    });

    test('all other states are not terminal', () {
      final nonTerminal = CallingState.values
          .where((s) => s != CallingState.declined && s != CallingState.released);
      for (final s in nonTerminal) {
        expect(s.isTerminal, isFalse, reason: '${s.name} should not be terminal');
      }
    });
  });

  group('CallingState.allowedNextStates', () {
    test('selected -> extended, declined', () {
      expect(
        CallingState.selected.allowedNextStates,
        [CallingState.extended, CallingState.declined],
      );
    });

    test('extended -> accepted, declined', () {
      expect(
        CallingState.extended.allowedNextStates,
        [CallingState.accepted, CallingState.declined],
      );
    });

    test('accepted -> sustained, released', () {
      expect(
        CallingState.accepted.allowedNextStates,
        [CallingState.sustained, CallingState.released],
      );
    });

    test('sustained -> setApart, released', () {
      expect(
        CallingState.sustained.allowedNextStates,
        [CallingState.setApart, CallingState.released],
      );
    });

    test('setApart -> active, released', () {
      expect(
        CallingState.setApart.allowedNextStates,
        [CallingState.active, CallingState.released],
      );
    });

    test('active -> released', () {
      expect(
        CallingState.active.allowedNextStates,
        [CallingState.released],
      );
    });

    test('terminal states have no allowed next states', () {
      expect(CallingState.declined.allowedNextStates, isEmpty);
      expect(CallingState.released.allowedNextStates, isEmpty);
    });

    test('no transition ever leads back to selected', () {
      // The `selected` state is only reachable as the initial event.
      for (final s in CallingState.values) {
        expect(
          s.allowedNextStates.contains(CallingState.selected),
          isFalse,
          reason: '${s.name} should not transition to selected',
        );
      }
    });

    test('every allowed next state is legal (never terminal + more transitions)',
        () {
      // If a state is terminal we should have no transitions from it. The
      // reverse (transitions from a state can *land on* a terminal state) is
      // fine and expected (declined / released).
      for (final s in CallingState.values) {
        if (s.isTerminal) {
          expect(s.allowedNextStates, isEmpty);
        }
      }
    });
  });
}
