import 'dart:convert';
import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/services/backup_service.dart';
import 'package:omr_app/services/exam_summary_service.dart';
import 'package:omr_app/services/local_data_store.dart';

class ExportService {
  ExportService._();
  static final ExportService instance = ExportService._();

  /// Export scan results to CSV file
  Future<File?> exportResultsToCsv({
    String? subjectId,
    String? sectionName,
    String? fileName,
  }) async {
    try {
      final students = await LocalDataStore.instance.fetchStudents();
      final studentIndex = <String, Student>{
        for (final student in students) student.omrId: student,
      };
      final results = (await LocalDataStore.instance.fetchScanResults(
        subjectId: subjectId,
        sectionName: sectionName,
      ))
          .where((result) => !result.requiresReview)
          .toList();
      _sortResultsByStudentName(results, studentIndex);
      if (results.isEmpty) return null;

      final rows = <List<dynamic>>[
        [
          'Student ID',
          'OMR ID',
          'Name',
          'Section',
          'Subject',
          'Score',
          'Total',
          'Percentage',
          'Status',
          'Scan Date'
        ],
      ];

      for (final result in results) {
        final student = studentIndex[result.studentOmrId];
        rows.add([
          student?.schoolId ?? '',
          result.studentOmrId,
          student?.name ?? 'Unknown',
          student?.section ?? '',
          result.subjectName,
          result.scoreDisplay,
          result.totalQuestions,
          '${result.percentage.toStringAsFixed(1)}%',
          result.passed ? 'PASSED' : 'FAILED',
          result.scanTime.toIso8601String(),
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final file = await _writeToFile(
        csv,
        fileName ?? 'omr_results_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      return file;
    } catch (e) {
      debugPrint('CSV export failed: $e');
      return null;
    }
  }

  /// Export all students to CSV
  Future<File?> exportStudentsToCsv(
      {String? sectionName, String? fileName}) async {
    try {
      final students = await LocalDataStore.instance.fetchStudents(
        sectionName: sectionName,
      );
      if (students.isEmpty) return null;

      final rows = <List<dynamic>>[
        [
          'Student ID',
          'OMR ID',
          'Name',
          'Section',
          'Last Score',
          'Last Scan Date'
        ],
      ];

      for (final student in students) {
        rows.add([
          student.schoolId,
          student.omrId,
          student.name,
          student.section,
          student.scoreDisplay,
          student.scanDate?.toIso8601String() ?? '',
        ]);
      }

      final csv = const ListToCsvConverter().convert(rows);
      final file = await _writeToFile(
        csv,
        fileName ?? 'students_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
      return file;
    } catch (e) {
      debugPrint('Student CSV export failed: $e');
      return null;
    }
  }

  /// Export results to PDF report
  Future<File?> exportResultsToPdf({
    String? subjectId,
    String? sectionName,
    String? fileName,
  }) async {
    try {
      final students = await LocalDataStore.instance.fetchStudents();
      final studentIndex = <String, Student>{
        for (final student in students) student.omrId: student,
      };
      final results = (await LocalDataStore.instance.fetchScanResults(
        subjectId: subjectId,
        sectionName: sectionName,
      ))
          .where((result) => !result.requiresReview)
          .toList();
      _sortResultsByStudentName(results, studentIndex);
      if (results.isEmpty) return null;

      final pdf = pw.Document();

      // Get subject name for title
      String title = 'OMR Scan Results';
      if (subjectId != null) {
        final subjects = await LocalDataStore.instance.fetchSubjects();
        final subject =
            subjects.where((entry) => entry.id == subjectId).firstOrNull;
        if (subject != null) title = '${subject.name} - Results';
      }
      if (sectionName != null) {
        title += ' ($sectionName)';
      }

      // Calculate summary stats
      final totalScans = results.length;
      final avgScore = results.isEmpty
          ? 0.0
          : results.map((r) => r.percentage).reduce((a, b) => a + b) /
              totalScans;
      final passCount = results.where((r) => r.passed).length;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Generated: ${DateTime.now().toString().split('.')[0]}',
                  style: const pw.TextStyle(
                      fontSize: 10, color: PdfColors.grey700)),
              pw.Divider(),
            ],
          ),
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('PHINMA COC OMR System',
                  style: const pw.TextStyle(fontSize: 8)),
              pw.Text('Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
          build: (context) => [
            // Summary box
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  _buildStatColumn('Total Scans', '$totalScans'),
                  _buildStatColumn(
                      'Average', '${avgScore.toStringAsFixed(1)}%'),
                  _buildStatColumn('Passed', '$passCount'),
                  _buildStatColumn('Failed', '${totalScans - passCount}'),
                  _buildStatColumn('Pass Rate',
                      '${((passCount / totalScans) * 100).toStringAsFixed(1)}%'),
                ],
              ),
            ),
            pw.SizedBox(height: 16),

            // Results table
            pw.TableHelper.fromTextArray(
              headerStyle:
                  pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 9),
              cellStyle: const pw.TextStyle(fontSize: 8),
              headerDecoration:
                  const pw.BoxDecoration(color: PdfColors.grey300),
              cellAlignments: {
                0: pw.Alignment.centerLeft,
                1: pw.Alignment.centerLeft,
                2: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
              },
              headers: ['Student ID', 'Name', 'Score', 'Percentage', 'Status'],
              data: results.map((r) {
                final student = studentIndex[r.studentOmrId];
                return [
                  student?.schoolId ?? r.studentOmrId,
                  student?.name ?? 'Unknown',
                  '${r.scoreDisplay}/${r.totalQuestions}',
                  '${r.percentage.toStringAsFixed(1)}%',
                  r.passed ? 'PASSED' : 'FAILED',
                ];
              }).toList(),
            ),
          ],
        ),
      );

      final bytes = await pdf.save();
      final file = await _writeToFile(
        bytes,
        fileName ?? 'omr_report_${DateTime.now().millisecondsSinceEpoch}.pdf',
        isBinary: true,
      );
      return file;
    } catch (e) {
      debugPrint('PDF export failed: $e');
      return null;
    }
  }

  /// Share exam summary report (section stats + top missed questions).
  Future<bool> shareExamSummaryPdf({
    required Subject subject,
    required String sectionName,
  }) async {
    final file = await exportExamSummaryPdf(
      subject: subject,
      sectionName: sectionName,
    );
    if (file == null) {
      return false;
    }
    await shareFile(file);
    await LocalDataStore.instance.recordExport(sectionName);
    return true;
  }

  Future<bool> shareExamSummaryCsv({
    required Subject subject,
    required String sectionName,
  }) async {
    final file = await exportExamSummaryCsv(
      subject: subject,
      sectionName: sectionName,
    );
    if (file == null) {
      return false;
    }
    await shareFile(file);
    await LocalDataStore.instance.recordExport(sectionName);
    return true;
  }

  Future<File?> exportExamSummaryPdf({
    required Subject subject,
    required String sectionName,
    String? fileName,
  }) async {
    try {
      final report = await ExamSummaryService.build(
        subject: subject,
        sectionName: sectionName,
      );
      if (report == null) {
        return null;
      }

      final pdf = pw.Document();
      final dateLabel = _formatReportDate(report.examDate ?? report.generatedAt);

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(32),
          header: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Exam Summary Report',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Cagayan de Oro College · PHINMA Education Network',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey700,
                ),
              ),
              pw.Divider(),
            ],
          ),
          footer: (context) => pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                'COC OMR',
                style: const pw.TextStyle(fontSize: 8),
              ),
              pw.Text(
                'Page ${context.pageNumber} of ${context.pagesCount}',
                style: const pw.TextStyle(fontSize: 8),
              ),
            ],
          ),
          build: (context) => [
            pw.Text(
              '${report.subjectName} · ${report.sectionName}',
              style: pw.TextStyle(
                fontSize: 16,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              'Exam date: $dateLabel',
              style: const pw.TextStyle(fontSize: 11),
            ),
            pw.Text(
              'Generated: ${_formatReportDateTime(report.generatedAt)}',
              style: const pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Container(
              padding: const pw.EdgeInsets.all(12),
              decoration: pw.BoxDecoration(
                color: PdfColors.grey100,
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Wrap(
                spacing: 18,
                runSpacing: 10,
                children: [
                  _buildStatColumn('Roster', '${report.rosterCount}'),
                  _buildStatColumn('Scanned', '${report.scannedCount}'),
                  _buildStatColumn(
                    'Class average',
                    '${report.averagePercentage.toStringAsFixed(1)}%',
                  ),
                  _buildStatColumn(
                    'Pass rate',
                    '${report.passRate.toStringAsFixed(1)}%',
                  ),
                  _buildStatColumn('Passed', '${report.passedCount}'),
                  _buildStatColumn('Failed', '${report.failedCount}'),
                  if (report.pendingReviewCount > 0)
                    _buildStatColumn(
                      'Needs review',
                      '${report.pendingReviewCount}',
                    ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Passing score: ${report.passingScorePoints}/${report.totalQuestions} '
              '(${report.passThresholdPercent.toStringAsFixed(0)}%)',
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 18),
            pw.Text(
              'Top missed questions',
              style: pw.TextStyle(
                fontSize: 14,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 8),
            if (report.topMissedQuestions.isEmpty)
              pw.Text(
                'No graded responses yet for item analysis.',
                style: const pw.TextStyle(fontSize: 10),
              )
            else
              pw.TableHelper.fromTextArray(
                headerStyle: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 9,
                ),
                cellStyle: const pw.TextStyle(fontSize: 9),
                headerDecoration:
                    const pw.BoxDecoration(color: PdfColors.grey300),
                headers: [
                  'Q#',
                  'Answer',
                  'Attempts',
                  'Correct',
                  'Missed',
                  '% Correct',
                ],
                data: report.topMissedQuestions
                    .map(
                      (item) => [
                        '${item.questionNumber}',
                        item.correctAnswer,
                        '${item.attempts}',
                        '${item.correctCount}',
                        '${item.missedCount}',
                        '${item.percentCorrect.toStringAsFixed(1)}%',
                      ],
                    )
                    .toList(),
              ),
            if (report.pendingReviewCount > 0) ...[
              pw.SizedBox(height: 16),
              pw.Text(
                'Note: ${report.pendingReviewCount} scan(s) still need review '
                'and are excluded from the averages above.',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
            ],
          ],
        ),
      );

      final bytes = await pdf.save();
      final safeSubject =
          subject.name.replaceAll(RegExp(r'[^\w\-]+'), '_').toLowerCase();
      final safeSection =
          sectionName.replaceAll(RegExp(r'[^\w\-]+'), '_').toLowerCase();
      return _writeToFile(
        bytes,
        fileName ??
            'exam_summary_${safeSubject}_${safeSection}_${DateTime.now().millisecondsSinceEpoch}.pdf',
        isBinary: true,
      );
    } catch (error) {
      debugPrint('Exam summary PDF export failed: $error');
      return null;
    }
  }

  Future<File?> exportExamSummaryCsv({
    required Subject subject,
    required String sectionName,
    String? fileName,
  }) async {
    try {
      final report = await ExamSummaryService.build(
        subject: subject,
        sectionName: sectionName,
      );
      if (report == null) {
        return null;
      }

      final rows = <List<dynamic>>[
        ['Exam Summary Report'],
        ['Section', report.sectionName],
        ['Subject', report.subjectName],
        [
          'Exam date',
          _formatReportDate(report.examDate ?? report.generatedAt),
        ],
        ['Generated', _formatReportDateTime(report.generatedAt)],
        [],
        ['Roster students', report.rosterCount],
        ['Scanned students', report.scannedCount],
        [
          'Class average (%)',
          report.averagePercentage.toStringAsFixed(1),
        ],
        ['Pass rate (%)', report.passRate.toStringAsFixed(1)],
        ['Passed', report.passedCount],
        ['Failed', report.failedCount],
        ['Passing score', report.passingScorePoints],
        ['Total questions', report.totalQuestions],
        ['Needs review', report.pendingReviewCount],
        [],
        [
          'Question',
          'Correct answer',
          'Attempts',
          'Correct',
          'Missed',
          'Percent correct',
        ],
        ...report.topMissedQuestions.map(
          (item) => [
            item.questionNumber,
            item.correctAnswer,
            item.attempts,
            item.correctCount,
            item.missedCount,
            item.percentCorrect.toStringAsFixed(1),
          ],
        ),
      ];

      final csv = const ListToCsvConverter().convert(rows);
      final safeSubject =
          subject.name.replaceAll(RegExp(r'[^\w\-]+'), '_').toLowerCase();
      final safeSection =
          sectionName.replaceAll(RegExp(r'[^\w\-]+'), '_').toLowerCase();
      return _writeToFile(
        csv,
        fileName ??
            'exam_summary_${safeSubject}_${safeSection}_${DateTime.now().millisecondsSinceEpoch}.csv',
      );
    } catch (error) {
      debugPrint('Exam summary CSV export failed: $error');
      return null;
    }
  }

  String _formatReportDate(DateTime value) {
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '${value.year}-$month-$day';
  }

  String _formatReportDateTime(DateTime value) {
    return _formatReportDate(value);
  }

  /// Share exported file
  Future<void> shareFile(File file) async {
    await Share.shareXFiles([XFile(file.path)]);
  }

  /// Export and share results as CSV
  Future<bool> shareResultsCsv({String? subjectId, String? sectionName}) async {
    final file = await exportResultsToCsv(
        subjectId: subjectId, sectionName: sectionName);
    if (file == null) return false;
    await shareFile(file);
    if (sectionName != null) {
      await LocalDataStore.instance.recordExport(sectionName);
    }
    return true;
  }

  /// Export and share results as PDF
  Future<bool> shareResultsPdf({String? subjectId, String? sectionName}) async {
    final file = await exportResultsToPdf(
        subjectId: subjectId, sectionName: sectionName);
    if (file == null) return false;
    await shareFile(file);
    if (sectionName != null) {
      await LocalDataStore.instance.recordExport(sectionName);
    }
    return true;
  }

  /// Create data backup
  Future<File?> createBackup() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final timestamp =
          DateTime.now().toIso8601String().replaceAll(':', '-').split('.')[0];
      final backupFile = File(
          '${directory.path}${Platform.pathSeparator}omr_backup_$timestamp.json');
      await backupFile.writeAsString(
        const JsonEncoder.withIndent('  ')
            .convert(BackupService.buildPayload()),
      );
      return backupFile;
    } catch (e) {
      debugPrint('Backup failed: $e');
      return null;
    }
  }

  void _sortResultsByStudentName(
    List<ScanResult> results,
    Map<String, Student> studentIndex,
  ) {
    results.sort((a, b) {
      final studentA = studentIndex[a.studentOmrId];
      final studentB = studentIndex[b.studentOmrId];
      return (studentA?.name ?? '').compareTo(studentB?.name ?? '');
    });
  }

  pw.Widget _buildStatColumn(String label, String value) {
    return pw.Column(
      children: [
        pw.Text(value,
            style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 2),
        pw.Text(label,
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
      ],
    );
  }

  Future<File> _writeToFile(dynamic content, String fileName,
      {bool isBinary = false}) async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    if (isBinary) {
      await file.writeAsBytes(content as List<int>);
    } else {
      await file.writeAsString(content as String);
    }
    return file;
  }
}
