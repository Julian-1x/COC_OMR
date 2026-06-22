import 'dart:io';

import 'package:excel/excel.dart';

void main(List<String> args) {
  final path = args.isNotEmpty
      ? args.first
      : r'D:\DOWNLOADS\StudentRoster2_with_20_more.xlsx';
  final bytes = File(path).readAsBytesSync();
  stdout.writeln('bytes: ${bytes.length}');
  try {
    final excel = Excel.decodeBytes(bytes);
    stdout.writeln('tables: ${excel.tables.keys}');
    for (final name in excel.tables.keys) {
      final sheet = excel.tables[name];
      if (sheet != null) {
        stdout.writeln('sheet $name rows: ${sheet.rows.length}');
        if (sheet.rows.isNotEmpty) {
          stdout.writeln('header: ${sheet.rows.first}');
        }
      }
    }
  } catch (e, st) {
    stdout.writeln('ERROR: $e');
    stdout.writeln(st);
  }
}
