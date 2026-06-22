import 'package:flutter_test/flutter_test.dart';
import 'package:omr_app/utils/section_program.dart';

void main() {
  test('programKey reads common section prefixes', () {
    expect(SectionProgram.programKey('BSIT-01'), 'BSIT');
    expect(SectionProgram.programKey('BSECE 2A'), 'BSECE');
    expect(SectionProgram.programKey('BSME_03'), 'BSME');
    expect(SectionProgram.programKey(''), 'OTHER');
  });

  test('groupTitle adds friendly program names when known', () {
    expect(
      SectionProgram.groupTitle('BSIT'),
      'BSIT · Information Technology',
    );
    expect(
      SectionProgram.groupTitle('BSECE'),
      'BSECE · Electronics Engineering',
    );
    expect(SectionProgram.groupTitle('CUSTOM'), 'CUSTOM');
  });

  test('sortedProgramKeys returns unique sorted codes', () {
    expect(
      SectionProgram.sortedProgramKeys([
        'BSIT-01',
        'BSECE-01',
        'BSIT-02',
      ]),
      ['BSECE', 'BSIT'],
    );
  });
}
