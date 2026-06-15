import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/pages/dashboard_page.dart';

void main() {
  setUp(() {
    resetOmrCounter();
    resetSubjectCounter();
    resetSheetCounter();

    globalStudentDatabase = [
      Student(
        schoolId: '2024001',
        omrId: '0001',
        name: 'Ava Cruz',
        section: 'BSIT-01',
        score: 2,
      ),
      Student(
        schoolId: '2024002',
        omrId: '0002',
        name: 'Liam Santos',
        section: 'BSIT-01',
      ),
      Student(
        schoolId: '2024003',
        omrId: '0003',
        name: 'Mia Reyes',
        section: 'BSIT-02',
      ),
    ];

    globalSections = [
      Section(name: 'BSIT-01'),
      Section(name: 'BSIT-02'),
    ];

    final mathSubject = Subject(
      name: 'Math',
      answerKey: const {
        1: 'A',
        2: 'B',
      },
      totalQuestions: 2,
      sectionNames: ['BSIT-01'],
    );
    final englishSubject = Subject(
      name: 'English',
      answerKey: const {
        1: 'C',
        2: 'D',
      },
      totalQuestions: 2,
      sectionNames: ['BSIT-01'],
    );
    final scienceSubject = Subject(
      name: 'Science',
      answerKey: const {
        1: 'A',
        2: 'C',
      },
      totalQuestions: 2,
      sectionNames: ['BSIT-02'],
    );

    globalSubjects = [
      mathSubject,
      englishSubject,
      scienceSubject,
    ];

    globalScanResults = [
      ScanResult(
        studentOmrId: '0001',
        subjectId: mathSubject.id,
        subjectName: 'Math',
        detectedAnswers: const {
          1: 'A',
          2: 'B',
        },
        correctnessMap: const {
          1: 1.0,
          2: 1.0,
        },
        score: 2,
        totalQuestions: 2,
        confidence: 0.98,
        scanTime: DateTime(2026, 3, 31, 9, 30),
      ),
    ];
    globalDeadlines = [];
    globalExportRecords = [];
    rebuildStudentIndex();
  });

  testWidgets('drawer shows hub title; home shows workflow and stats', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(initialData: DashboardPageData.fromMemory()),
      ),
    );

    await tester.pumpAndSettle();

    final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold));
    scaffoldState.openDrawer();
    await tester.pumpAndSettle();

    expect(find.text('COC OMR Hub'), findsOneWidget);
    expect(find.text('Home'), findsWidgets);

    scaffoldState.closeDrawer();
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('What to do next'), findsOneWidget);
    expect(find.textContaining('% complete'), findsOneWidget);
    expect(find.text('Start Scan'), findsOneWidget);
    expect(find.text('Import Roster'), findsOneWidget);
    expect(find.text('Answer Keys'), findsOneWidget);

    await tester.tap(find.text('Tools').last);
    await tester.pumpAndSettle();

    expect(find.text('Print Sheets'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Export Results'),
      120,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    expect(find.text('Export Results'), findsOneWidget);

    expect(find.text('Classes'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('classes tab opens section detail with student rows', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DashboardPage(initialData: DashboardPageData.fromMemory()),
      ),
    );

    await tester.pumpAndSettle();

    await tester.tap(find.text('Classes').last);
    await tester.pumpAndSettle();

    expect(find.text('BSIT-01'), findsWidgets);
    expect(find.text('1/2 subjects scanned'), findsOneWidget);

    await tester.tap(find.text('BSIT-01').first);
    await tester.pumpAndSettle();

    expect(find.text('BSIT-01'), findsWidgets);
    expect(find.text('Ava Cruz'), findsOneWidget);
    expect(find.text('2024001'), findsOneWidget);
    expect(find.text('0001'), findsWidgets);

    await tester.tap(find.byTooltip('Add subject'));
    await tester.pumpAndSettle();
    expect(find.text('Add Subject'), findsOneWidget);
  });
}
