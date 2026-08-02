import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/services/import_service.dart';
import 'package:omr_app/utils/roster_columns.dart';
import 'package:omr_app/utils/roster_spreadsheet.dart';

void main() {
  group('RosterColumnMap', () {
    test('detects ID, NAME, SECTION headers', () {
      final rows = [
        ['ID', 'NAME', 'SECTION'],
        ['0001', 'Alexander Cruz', 'STEM-11A'],
      ];

      final headerIndex = RosterColumnMap.detectHeaderRow(rows, _readCell);
      expect(headerIndex, 0);

      final header = rows[headerIndex]
          .map((cell) => RosterColumnMap.normalizeHeader(_readCell(cell)))
          .toList();
      final map = RosterColumnMap.fromHeader(header);

      expect(map.schoolIdIndex, 0);
      expect(map.nameIndex, 1);
      expect(map.sectionIndex, 2);
    });

    test('infers columns when headers are missing', () {
      final rows = [
        ['0001', 'Alexander Cruz', 'STEM-11A'],
        ['0002', 'Maria Santos', 'STEM-11A'],
      ];

      final map = RosterColumnMap.inferFromRows(rows, _readCell);
      expect(map, isNotNull);
      expect(map!.schoolIdIndex, 0);
      expect(map.nameIndex, 1);
      expect(map.sectionIndex, 2);
    });
    test('maps official school export headers and ignores extra columns', () {
      final header = [
        'session name',
        'campus',
        'student id',
        'student name',
        'gender',
        'college',
        'course',
        'subject',
        'section',
        'email',
      ];
      final map = RosterColumnMap.fromHeader(header);
      expect(map.schoolIdIndex, 2);
      expect(map.nameIndex, 3);
      expect(map.sectionIndex, 8);
    });

    test('does not treat COURSE as SECTION', () {
      final header = ['student id', 'student name', 'course', 'section'];
      final map = RosterColumnMap.fromHeader(header);
      expect(map.sectionIndex, 3);
    });

    test('does not treat SESSION NAME as student name', () {
      final header = ['session name', 'student id', 'student name', 'section'];
      final map = RosterColumnMap.fromHeader(header);
      expect(map.nameIndex, 2);
    });
  });

  group('RosterSpreadsheetDecoder', () {
    test('decodes simple CSV', () {
      final bytes = Uint8List.fromList('''Student ID,Name,Section
0001,Alex,STEM-11A
'''.codeUnits);
      final rows = RosterSpreadsheetDecoder.decode(
        bytes: bytes,
        extension: 'csv',
      );
      expect(rows.length, greaterThanOrEqualTo(2));
      expect(rows.first[0], 'Student ID');
    });

    test('decodes PHINMA Class_List_Report namespaced xlsx', () {
      final file = File('test/fixtures/Class_List_Report-3.xlsx');
      expect(file.existsSync(), isTrue);

      final rows = RosterSpreadsheetDecoder.decode(
        bytes: file.readAsBytesSync(),
        extension: 'xlsx',
        fileName: 'Class_List_Report-3.xlsx',
      );

      expect(rows.length, greaterThan(1));
      final header = rows.first.map((c) => c.toString().toUpperCase()).toList();
      expect(header, contains('STUDENT ID'));
      expect(header, contains('STUDENT NAME'));
      expect(header, contains('SECTION'));

      final map = RosterColumnMap.fromHeader(
        rows.first
            .map((c) => RosterColumnMap.normalizeHeader(c.toString()))
            .toList(),
      );
      expect(map.schoolIdIndex, 2);
      expect(map.nameIndex, 3);
      expect(map.sectionIndex, 8);

      final summary = ImportService.importRows(
        rows,
        fileName: 'Class_List_Report-3.xlsx',
      );
      expect(summary.imported + summary.updated, greaterThan(0));
    });

    test('decodes real teacher xlsx when fixture is present', () {
      const fixturePath = r'D:\DOWNLOADS\StudentRoster2_with_20_more.xlsx';
      final file = File(fixturePath);
      if (!file.existsSync()) {
        return;
      }

      final bytes = file.readAsBytesSync();
      final rows = RosterSpreadsheetDecoder.decode(
        bytes: bytes,
        extension: 'xlsx',
        fileName: 'StudentRoster2_with_20_more.xlsx',
      );

      expect(rows.length, greaterThan(1));
      expect(rows.first.map((c) => c.toString().toUpperCase()).join('|'), contains('ID'));

      final summary = ImportService.importRows(
        rows,
        fileName: 'StudentRoster2_with_20_more.xlsx',
      );
      expect(summary.imported + summary.updated, greaterThan(0));
    });
  });
}

String _readCell(dynamic value) => value?.toString().trim() ?? '';
