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
