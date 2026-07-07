import 'package:flutter_test/flutter_test.dart';
import 'package:lds_bishopric_tracker/features/callings/domain/entities/calling.dart';

void main() {
  group('Calling.fromMap', () {
    test('parses a full row', () {
      final c = Calling.fromMap({
        'id': 'cid',
        'member_id': 'mid',
        'title': 'Elders Quorum President',
        'organization': 'Elders Quorum',
        'notes': 'temporary',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-02T00:00:00Z',
      });

      expect(c.id, 'cid');
      expect(c.memberId, 'mid');
      expect(c.title, 'Elders Quorum President');
      expect(c.organization, 'Elders Quorum');
      expect(c.notes, 'temporary');
      expect(c.createdAt.toUtc(), DateTime.utc(2025, 1, 1));
      expect(c.updatedAt.toUtc(), DateTime.utc(2025, 1, 2));
    });

    test('leaves optional fields null when absent', () {
      final c = Calling.fromMap({
        'id': 'cid',
        'member_id': 'mid',
        'title': 'Ward Clerk',
        'organization': null,
        'notes': null,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      expect(c.organization, isNull);
      expect(c.notes, isNull);
    });
  });

  group('NewCalling.toInsert', () {
    test('always writes member_id and trimmed title', () {
      final map =
          const NewCalling(memberId: 'mid', title: '  Ward Clerk  ').toInsert();
      expect(map['member_id'], 'mid');
      expect(map['title'], 'Ward Clerk');
    });

    test('omits null and empty/whitespace-only optional fields', () {
      final map = const NewCalling(
        memberId: 'mid',
        title: 'Ward Clerk',
        organization: '',
        notes: '   ',
      ).toInsert();
      expect(map.containsKey('organization'), isFalse);
      expect(map.containsKey('notes'), isFalse);
    });

    test('trims non-empty optional fields', () {
      final map = const NewCalling(
        memberId: 'mid',
        title: 'Ward Clerk',
        organization: '  Bishopric  ',
        notes: '  first calling  ',
      ).toInsert();
      expect(map['organization'], 'Bishopric');
      expect(map['notes'], 'first calling');
    });
  });

  group('CallingUpdate.toUpdate', () {
    test('always writes title, organization, notes', () {
      final map = const CallingUpdate(title: 'Ward Clerk').toUpdate();
      expect(map.keys, containsAll(<String>['title', 'organization', 'notes']));
    });

    test('trims title', () {
      final map = const CallingUpdate(title: '  Ward Clerk  ').toUpdate();
      expect(map['title'], 'Ward Clerk');
    });

    test('trimmed-empty organization/notes become null (clears the column)', () {
      final map = const CallingUpdate(
        title: 'Ward Clerk',
        organization: '',
        notes: '   ',
      ).toUpdate();
      expect(map['organization'], isNull);
      expect(map['notes'], isNull);
    });

    test('null optional fields serialize as null', () {
      final map = const CallingUpdate(
        title: 'Ward Clerk',
        organization: null,
        notes: null,
      ).toUpdate();
      expect(map['organization'], isNull);
      expect(map['notes'], isNull);
    });

    test('trims non-empty optional fields', () {
      final map = const CallingUpdate(
        title: 'Ward Clerk',
        organization: '  Bishopric  ',
        notes: '  updated  ',
      ).toUpdate();
      expect(map['organization'], 'Bishopric');
      expect(map['notes'], 'updated');
    });
  });
}
