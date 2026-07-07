import 'package:flutter_test/flutter_test.dart';
import 'package:lds_bishopric_tracker/features/members/domain/entities/member.dart';

void main() {
  group('Member.fromMap', () {
    test('parses a fully-populated row', () {
      final m = Member.fromMap({
        'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
        'first_name': 'Jane',
        'last_name': 'Doe',
        'preferred_name': 'Janie',
        'phone': '555-0100',
        'email': 'jane@example.com',
        'notes': 'call after 6pm',
        'date_of_birth': '1985-04-15',
        'sex': 'female',
        'priesthood_office': 'none',
        'is_active': true,
        'created_at': '2025-01-01T00:00:00.000Z',
        'updated_at': '2025-01-02T12:00:00.000Z',
      });

      expect(m.id, 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
      expect(m.firstName, 'Jane');
      expect(m.lastName, 'Doe');
      expect(m.preferredName, 'Janie');
      expect(m.phone, '555-0100');
      expect(m.email, 'jane@example.com');
      expect(m.notes, 'call after 6pm');
      expect(m.dateOfBirth, DateTime(1985, 4, 15));
      expect(m.sex, 'female');
      expect(m.priesthoodOffice, 'none');
      expect(m.isActive, isTrue);
      expect(m.createdAt.toUtc(), DateTime.utc(2025, 1, 1));
      expect(m.updatedAt.toUtc(), DateTime.utc(2025, 1, 2, 12));
    });

    test('handles minimum row (only required fields + timestamps)', () {
      final m = Member.fromMap({
        'id': 'id',
        'first_name': 'A',
        'last_name': 'B',
        'preferred_name': null,
        'phone': null,
        'email': null,
        'notes': null,
        'date_of_birth': null,
        'sex': null,
        'priesthood_office': null,
        'is_active': true,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });

      expect(m.preferredName, isNull);
      expect(m.phone, isNull);
      expect(m.email, isNull);
      expect(m.notes, isNull);
      expect(m.dateOfBirth, isNull);
      expect(m.sex, isNull);
      expect(m.priesthoodOffice, isNull);
      expect(m.isActive, isTrue);
    });

    test('defaults isActive to true when the column is absent', () {
      final m = Member.fromMap({
        'id': 'id',
        'first_name': 'A',
        'last_name': 'B',
        // is_active omitted entirely
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      expect(m.isActive, isTrue);
    });

    test('reads is_active=false when explicitly set', () {
      final m = Member.fromMap({
        'id': 'id',
        'first_name': 'A',
        'last_name': 'B',
        'is_active': false,
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      expect(m.isActive, isFalse);
    });

    test('parses empty date_of_birth as null', () {
      final m = Member.fromMap({
        'id': 'id',
        'first_name': 'A',
        'last_name': 'B',
        'date_of_birth': '',
        'created_at': '2025-01-01T00:00:00Z',
        'updated_at': '2025-01-01T00:00:00Z',
      });
      expect(m.dateOfBirth, isNull);
    });
  });

  group('Member computed names', () {
    test('sortName is "Last, First"', () {
      final m = _member(firstName: 'Jane', lastName: 'Doe');
      expect(m.sortName, 'Doe, Jane');
    });

    test('displayName uses preferred name when non-empty', () {
      final m = _member(
        firstName: 'Jonathan',
        lastName: 'Smith',
        preferredName: 'Jon',
      );
      expect(m.displayName, 'Jon Smith');
    });

    test('displayName falls back to firstName when preferred is blank', () {
      final m1 = _member(firstName: 'Jane', lastName: 'Doe');
      final m2 = _member(firstName: 'Jane', lastName: 'Doe', preferredName: '');
      final m3 = _member(firstName: 'Jane', lastName: 'Doe', preferredName: '   ');
      expect(m1.displayName, 'Jane Doe');
      expect(m2.displayName, 'Jane Doe');
      expect(m3.displayName, 'Jane Doe');
    });
  });

  group('NewMember.toInsert', () {
    test('trims required fields', () {
      final map = const NewMember(firstName: '  Jane ', lastName: ' Doe  ')
          .toInsert();
      expect(map['first_name'], 'Jane');
      expect(map['last_name'], 'Doe');
    });

    test('omits nulls and empty/whitespace-only optionals', () {
      final map = const NewMember(
        firstName: 'Jane',
        lastName: 'Doe',
        preferredName: '',
        phone: '   ',
        email: null,
      ).toInsert();

      expect(map.containsKey('preferred_name'), isFalse);
      expect(map.containsKey('phone'), isFalse);
      expect(map.containsKey('email'), isFalse);
      expect(map.containsKey('notes'), isFalse);
      expect(map.containsKey('sex'), isFalse);
      expect(map.containsKey('priesthood_office'), isFalse);
      expect(map.containsKey('date_of_birth'), isFalse);
    });

    test('includes and trims optional strings when present', () {
      final map = const NewMember(
        firstName: 'Jane',
        lastName: 'Doe',
        preferredName: ' Janie ',
        phone: '555-0100',
        email: 'jane@example.com',
        notes: 'hi',
        sex: 'female',
        priesthoodOffice: 'none',
      ).toInsert();

      expect(map['preferred_name'], 'Janie');
      expect(map['phone'], '555-0100');
      expect(map['email'], 'jane@example.com');
      expect(map['notes'], 'hi');
      expect(map['sex'], 'female');
      expect(map['priesthood_office'], 'none');
    });

    test('formats dateOfBirth as YYYY-MM-DD', () {
      final map = NewMember(
        firstName: 'Jane',
        lastName: 'Doe',
        dateOfBirth: DateTime(1985, 4, 5),
      ).toInsert();
      expect(map['date_of_birth'], '1985-04-05');
    });

    test('does not include is_active (DB default applies)', () {
      final map = const NewMember(firstName: 'A', lastName: 'B').toInsert();
      expect(map.containsKey('is_active'), isFalse);
    });
  });

  group('MemberUpdate.toUpdate', () {
    test('writes every column every save', () {
      final map = const MemberUpdate(
        firstName: 'Jane',
        lastName: 'Doe',
        preferredName: 'Janie',
        phone: '555-0100',
        email: 'jane@example.com',
        notes: 'hi',
        sex: 'female',
        priesthoodOffice: 'none',
        isActive: true,
      ).toUpdate();

      expect(map.keys, containsAll(<String>[
        'first_name',
        'last_name',
        'preferred_name',
        'phone',
        'email',
        'notes',
        'sex',
        'priesthood_office',
        'date_of_birth',
        'is_active',
      ]));
    });

    test('trimmed-empty optional fields become null (clears the column)', () {
      final map = const MemberUpdate(
        firstName: 'Jane',
        lastName: 'Doe',
        preferredName: '',
        phone: '   ',
        email: null,
        notes: '',
        sex: '',
        priesthoodOffice: null,
        isActive: true,
      ).toUpdate();

      expect(map['preferred_name'], isNull);
      expect(map['phone'], isNull);
      expect(map['email'], isNull);
      expect(map['notes'], isNull);
      expect(map['sex'], isNull);
      expect(map['priesthood_office'], isNull);
      expect(map['date_of_birth'], isNull);
    });

    test('trims required first_name and last_name', () {
      final map = const MemberUpdate(
        firstName: '  Jane ',
        lastName: ' Doe  ',
        isActive: true,
      ).toUpdate();
      expect(map['first_name'], 'Jane');
      expect(map['last_name'], 'Doe');
    });

    test('formats a set dateOfBirth as YYYY-MM-DD', () {
      final map = MemberUpdate(
        firstName: 'Jane',
        lastName: 'Doe',
        dateOfBirth: DateTime(1985, 4, 5),
        isActive: true,
      ).toUpdate();
      expect(map['date_of_birth'], '1985-04-05');
    });

    test('writes isActive verbatim', () {
      final active = const MemberUpdate(
        firstName: 'A',
        lastName: 'B',
        isActive: true,
      ).toUpdate();
      final inactive = const MemberUpdate(
        firstName: 'A',
        lastName: 'B',
        isActive: false,
      ).toUpdate();
      expect(active['is_active'], isTrue);
      expect(inactive['is_active'], isFalse);
    });
  });
}

/// Small factory to keep individual test setups readable.
Member _member({
  required String firstName,
  required String lastName,
  String? preferredName,
}) {
  return Member(
    id: 'id',
    firstName: firstName,
    lastName: lastName,
    preferredName: preferredName,
    isActive: true,
    createdAt: DateTime.utc(2025, 1, 1),
    updatedAt: DateTime.utc(2025, 1, 1),
  );
}
