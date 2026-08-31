import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/omr_template_specs.dart';

/// How the teacher defined this saved sheet shape.
enum CustomSheetLayoutInputMode {
  byQuestions('by_questions'),
  byGrid('by_grid');

  const CustomSheetLayoutInputMode(this.id);
  final String id;

  static CustomSheetLayoutInputMode fromId(String? raw) {
    final value = raw?.trim().toLowerCase();
    for (final mode in values) {
      if (mode.id == value) {
        return mode;
      }
    }
    return byQuestions;
  }
}

/// Saved custom answer-sheet layout (local library). Applied at print time.
class CustomSheetLayout {
  const CustomSheetLayout({
    required this.id,
    required this.name,
    this.description,
    required this.totalQuestions,
    required this.optionsCount,
    required this.layoutShape,
    required this.gridColumns,
    required this.gridRows,
    required this.inputMode,
    required this.createdAt,
    this.lastUsedAt,
  });

  final String id;
  final String name;
  final String? description;
  final int totalQuestions;
  final int optionsCount;
  final String layoutShape;
  final int gridColumns;
  final int gridRows;
  final CustomSheetLayoutInputMode inputMode;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  OmrLayoutForm get layoutForm => OmrLayoutForm.fromId(layoutShape);

  OmrLayoutProfile get layoutProfile => toProfile();

  OmrLayoutProfile toProfile() {
    final fit = inputMode == CustomSheetLayoutInputMode.byGrid
        ? OmrLayoutProfile.tryComputeExplicitGrid(
            columns: gridColumns,
            rows: gridRows,
            optionsCount: optionsCount,
            form: layoutForm,
          )
        : OmrLayoutProfile.tryCompute(
            itemCount: totalQuestions,
            optionsCount: optionsCount,
            form: layoutForm,
          );
    if (fit.profile != null) {
      return fit.profile!;
    }
    return OmrLayoutProfile.resolve(
      totalQuestions: totalQuestions,
      useCustomLayout: true,
      optionsCount: optionsCount,
      form: layoutForm,
    );
  }

  String get previewSubtitle {
    final profile = layoutProfile;
    return '${profile.itemCount} Q · ${profile.optionsCount} opts · '
        '${profile.geometry.printOrientationLabel} · ${layoutForm.pageFill.teacherLabel} '
        '(${profile.grid.columns}×${profile.grid.rows})';
  }

  /// Null when this layout is allowed for print + scan grading.
  String? get examReadyScanError => null;

  /// Returns null when layout is valid for the subject.
  String? validateForSubject(Subject subject) {
    if (subject.totalQuestions != totalQuestions) {
      return 'This layout is for $totalQuestions questions, but '
          '${subject.displayName} has ${subject.totalQuestions}. '
          'Create a matching answer key or pick another layout.';
    }
    final fit = inputMode == CustomSheetLayoutInputMode.byGrid
        ? OmrLayoutProfile.tryComputeExplicitGrid(
            columns: gridColumns,
            rows: gridRows,
            optionsCount: optionsCount,
            form: layoutForm,
          )
        : OmrLayoutProfile.tryCompute(
            itemCount: totalQuestions,
            optionsCount: optionsCount,
            form: layoutForm,
          );
    if (!fit.isOk) {
      return fit.errorMessage ?? 'This layout is no longer scannable.';
    }
    return null;
  }

  Subject applyToSubject(Subject subject) {
    return subject.copyWith(
      useCustomLayout: true,
      optionsCount: optionsCount,
      layoutShape: layoutForm.id,
      customLayoutId: id,
      customGridColumns: gridColumns,
      customGridRows: gridRows,
    );
  }

  Subject clearFromSubject(Subject subject) {
    return subject.copyWith(
      useCustomLayout: false,
      optionsCount: OmrPageConstants.answerOptionsCount,
      layoutShape: 'lengthwise_full',
      clearCustomLayoutId: true,
      clearCustomGrid: true,
    );
  }

  /// Blank subject for sample printing from the library.
  Subject toBlankSampleSubject() {
    return Subject(
      name: name,
      answerKey: const <int, dynamic>{},
      totalQuestions: totalQuestions,
      useCustomLayout: true,
      optionsCount: optionsCount,
      layoutShape: layoutForm.id,
      customLayoutId: id,
      customGridColumns: gridColumns,
      customGridRows: gridRows,
    );
  }

  factory CustomSheetLayout.create({
    required String name,
    String? description,
    required int totalQuestions,
    required int optionsCount,
    required OmrLayoutForm form,
    required CustomSheetLayoutInputMode inputMode,
    int? gridColumns,
    int? gridRows,
  }) {
    final fit = inputMode == CustomSheetLayoutInputMode.byGrid
        ? OmrLayoutProfile.tryComputeExplicitGrid(
            columns: gridColumns ?? 1,
            rows: gridRows ?? 1,
            optionsCount: optionsCount,
            form: form,
          )
        : OmrLayoutProfile.tryCompute(
            itemCount: totalQuestions,
            optionsCount: optionsCount,
            form: form,
          );
    final profile = fit.profile;
    return CustomSheetLayout(
      id: 'csl_${DateTime.now().millisecondsSinceEpoch}',
      name: name.trim(),
      description: description?.trim(),
      totalQuestions: totalQuestions,
      optionsCount: optionsCount.clamp(2, 5),
      layoutShape: form.id,
      gridColumns: profile?.grid.columns ?? gridColumns ?? 1,
      gridRows: profile?.grid.rows ?? gridRows ?? 1,
      inputMode: inputMode,
      createdAt: DateTime.now(),
    );
  }

  CustomSheetLayout copyWith({
    String? name,
    String? description,
    int? totalQuestions,
    int? optionsCount,
    String? layoutShape,
    int? gridColumns,
    int? gridRows,
    CustomSheetLayoutInputMode? inputMode,
    DateTime? lastUsedAt,
  }) {
    return CustomSheetLayout(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      totalQuestions: totalQuestions ?? this.totalQuestions,
      optionsCount: optionsCount ?? this.optionsCount,
      layoutShape: layoutShape ?? this.layoutShape,
      gridColumns: gridColumns ?? this.gridColumns,
      gridRows: gridRows ?? this.gridRows,
      inputMode: inputMode ?? this.inputMode,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'totalQuestions': totalQuestions,
        'optionsCount': optionsCount,
        'layoutShape': layoutShape,
        'gridColumns': gridColumns,
        'gridRows': gridRows,
        'inputMode': inputMode.id,
        'createdAt': createdAt.toIso8601String(),
        'lastUsedAt': lastUsedAt?.toIso8601String(),
      };

  factory CustomSheetLayout.fromJson(Map<String, dynamic> json) {
    return CustomSheetLayout(
      id: json['id'] as String? ??
          'csl_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Unnamed layout',
      description: json['description'] as String?,
      totalQuestions: json['totalQuestions'] as int? ?? 50,
      optionsCount: json['optionsCount'] as int? ??
          OmrPageConstants.answerOptionsCount,
      layoutShape: json['layoutShape'] as String? ?? 'lengthwise_full',
      gridColumns: json['gridColumns'] as int? ?? 5,
      gridRows: json['gridRows'] as int? ?? 10,
      inputMode:
          CustomSheetLayoutInputMode.fromId(json['inputMode'] as String?),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      lastUsedAt: json['lastUsedAt'] != null
          ? DateTime.tryParse(json['lastUsedAt'] as String)
          : null,
    );
  }
}

List<CustomSheetLayout> globalCustomSheetLayouts = [];
