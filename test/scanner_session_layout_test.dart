import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';
import 'package:omr_app/services/scanner_session_layout.dart';

void main() {
  test('session layout matches template for each supported item count', () {
    const counts = <int>[30, 40, 50, 60, 70, 80, 90, 100];
    for (final count in counts) {
      final subject = Subject(
        id: 'SUB-$count',
        name: 'Math $count',
        answerKey: {for (int i = 1; i <= count; i++) i: 'A'},
        totalQuestions: count,
      );
      final session = ScannerSessionLayout.fromSubject(subject);
      final template = OmrTemplateSpec.forItemCount(count);
      final native = session.toNativeMap();

      expect(session.templateId, template.templateId);
      expect(session.totalQuestions, count);
      expect(native['template'], template.templateId);
      expect(native['cols'], template.columns);
      expect(native['rows'], template.rows);
      expect(native['gridTop'], OmrPageConstants.answerRowsTop);
      expect(native['rowHeight'], template.rowHeight);
      expect(native['bubbleSpacingX'], template.bubbleSpacingX);
    }
  });
}
