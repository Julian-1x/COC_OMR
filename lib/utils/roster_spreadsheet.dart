import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';

/// Reads roster spreadsheets from CSV or Excel with multiple decode strategies.
class RosterSpreadsheetDecoder {
  const RosterSpreadsheetDecoder._();

  static List<List<dynamic>> decode({
    required Uint8List bytes,
    String? extension,
    String? fileName,
  }) {
    if (bytes.isEmpty) {
      throw const FormatException('The selected file is empty.');
    }

    final ext = _resolveExtension(extension, fileName, bytes);
    if (ext == 'csv') {
      return _decodeCsv(bytes);
    }
    if (ext == 'xlsx') {
      return _decodeXlsx(bytes);
    }

    throw FormatException(
      'Unsupported file type "$ext". Save the roster as .xlsx or .csv.',
    );
  }

  static String _resolveExtension(
    String? extension,
    String? fileName,
    Uint8List bytes,
  ) {
    final fromName = _extensionFromName(fileName ?? '');
    final normalized = (extension ?? fromName).trim().toLowerCase();
    if (normalized == 'xlsx' || normalized == 'csv') {
      return normalized;
    }
    if (_looksLikeZip(bytes)) {
      return 'xlsx';
    }
    if (_looksLikeCsv(bytes)) {
      return 'csv';
    }
    return normalized.isEmpty ? 'xlsx' : normalized;
  }

  static String _extensionFromName(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot >= fileName.length - 1) {
      return '';
    }
    return fileName.substring(dot + 1).toLowerCase();
  }

  static bool _looksLikeZip(Uint8List bytes) =>
      bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;

  static bool _looksLikeCsv(Uint8List bytes) {
    if (_looksLikeZip(bytes)) {
      return false;
    }
    final sample = utf8.decode(bytes.take(512).toList(), allowMalformed: true);
    return sample.contains(',') || sample.contains('\t');
  }

  static List<List<dynamic>> _decodeCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) {
      text = text.substring(1);
    }
    text = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return const CsvToListConverter(shouldParseNumbers: false, eol: '\n')
        .convert(text);
  }

  static List<List<dynamic>> _decodeXlsx(Uint8List bytes) {
    final errors = <String>[];

    try {
      final rows = _decodeXlsxWithExcelPackage(bytes);
      if (rows.isNotEmpty) {
        return rows;
      }
      errors.add('Excel package returned no rows');
    } catch (error) {
      errors.add('Excel package: $error');
    }

    try {
      final rows = _decodeXlsxOoxml(bytes);
      if (rows.isNotEmpty) {
        return rows;
      }
      errors.add('OOXML fallback returned no rows');
    } catch (error) {
      errors.add('OOXML fallback: $error');
    }

    debugPrint('Roster xlsx decode failed:\n${errors.join('\n')}');
    throw const FormatException(
      'Could not read that Excel file. Try Save As → .xlsx or export as .csv, '
      'with Student ID, Name, and Section columns.',
    );
  }

  static List<List<dynamic>> _decodeXlsxWithExcelPackage(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    for (final tableName in excel.tables.keys) {
      final sheet = excel.tables[tableName];
      if (sheet == null || sheet.rows.isEmpty) {
        continue;
      }
      final rows = sheet.rows
          .map((row) => row.map(_excelCellValue).toList())
          .where((row) => row.any((cell) => cell.toString().trim().isNotEmpty))
          .toList();
      if (rows.isNotEmpty) {
        return rows;
      }
    }
    return const <List<dynamic>>[];
  }

  static dynamic _excelCellValue(dynamic cell) {
    if (cell is Data) {
      return cell.value;
    }
    return cell;
  }

  /// Minimal Office Open XML reader for simple single-sheet rosters.
  static List<List<dynamic>> _decodeXlsxOoxml(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);
    final sheetXml = _firstWorksheetXml(archive);
    if (sheetXml == null) {
      throw const FormatException('No worksheet found in workbook');
    }
    return _parseWorksheetXml(sheetXml, sharedStrings);
  }

  static List<String> _readSharedStrings(Archive archive) {
    final matches = archive.files.where((entry) => entry.name == 'xl/sharedStrings.xml');
    if (matches.isEmpty) {
      return const <String>[];
    }
    final file = matches.first;

    final xml = utf8.decode(file.content as List<int>, allowMalformed: true);
    final strings = <String>[];
    final siPattern = RegExp(r'<si[^>]*>(.*?)</si>', dotAll: true);
    for (final si in siPattern.allMatches(xml)) {
      final chunk = si.group(1) ?? '';
      final text = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
          .allMatches(chunk)
          .map((match) => _unescapeXml(match.group(1) ?? ''))
          .join();
      strings.add(text);
    }
    return strings;
  }

  static ArchiveFile? _firstWorksheetXml(Archive archive) {
    final sheets = archive.files
        .where(
          (entry) =>
              entry.name.startsWith('xl/worksheets/sheet') &&
              entry.name.endsWith('.xml'),
        )
        .toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (sheets.isEmpty) {
      return null;
    }
    return sheets.first;
  }

  static List<List<dynamic>> _parseWorksheetXml(
    ArchiveFile sheetFile,
    List<String> sharedStrings,
  ) {
    final xml = utf8.decode(sheetFile.content as List<int>, allowMalformed: true);
    final rowPattern = RegExp(r'<row[^>]*>(.*?)</row>', dotAll: true);
    final cellPattern = RegExp(r'<c\b([^>]*)>(.*?)</c>', dotAll: true);

    final rows = <int, Map<int, String>>{};
    for (final rowMatch in rowPattern.allMatches(xml)) {
      final rowBody = rowMatch.group(1) ?? '';
      for (final cellMatch in cellPattern.allMatches(rowBody)) {
        final attrs = cellMatch.group(1) ?? '';
        final body = cellMatch.group(2) ?? '';
        final refMatch = RegExp(r'\br="([A-Z]+)(\d+)"').firstMatch(attrs);
        if (refMatch == null) {
          continue;
        }
        final colLetters = refMatch.group(1) ?? 'A';
        final rowNumber = int.tryParse(refMatch.group(2) ?? '') ?? 0;
        if (rowNumber <= 0) {
          continue;
        }

        final colIndex = _columnLettersToIndex(colLetters);
        final value = _readOoxmlCellValue(attrs, body, sharedStrings);
        rows.putIfAbsent(rowNumber, () => <int, String>{})[colIndex] = value;
      }
    }

    if (rows.isEmpty) {
      return const <List<dynamic>>[];
    }

    final sortedRowNumbers = rows.keys.toList()..sort();
    final maxCol = rows.values.fold<int>(
      0,
      (max, row) => row.keys.fold(max, (inner, key) => key > inner ? key : inner),
    );

    return sortedRowNumbers.map((rowNumber) {
      final cells = rows[rowNumber]!;
      return List<dynamic>.generate(maxCol + 1, (index) => cells[index] ?? '');
    }).toList();
  }

  static String _readOoxmlCellValue(
    String attrs,
    String body,
    List<String> sharedStrings,
  ) {
    final typeMatch = RegExp(r'\bt="([^"]+)"').firstMatch(attrs);
    final cellType = typeMatch?.group(1);

    final inlineText = RegExp(r'<t[^>]*>(.*?)</t>', dotAll: true)
        .firstMatch(body)
        ?.group(1);
    if (inlineText != null) {
      return _unescapeXml(inlineText);
    }

    final rawValue =
        RegExp(r'<v>(.*?)</v>', dotAll: true).firstMatch(body)?.group(1);
    if (rawValue == null) {
      return '';
    }

    if (cellType == 's') {
      final index = int.tryParse(rawValue.trim());
      if (index != null && index >= 0 && index < sharedStrings.length) {
        return sharedStrings[index];
      }
    }

    return _unescapeXml(rawValue);
  }

  static int _columnLettersToIndex(String letters) {
    var index = 0;
    for (var i = 0; i < letters.length; i++) {
      index = index * 26 + (letters.codeUnitAt(i) - 64);
    }
    return index - 1;
  }

  static String _unescapeXml(String value) => value
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&#10;', '\n')
      .trim();
}
