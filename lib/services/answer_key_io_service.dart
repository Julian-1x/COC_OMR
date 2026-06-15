import 'dart:convert';

/// Service for importing and exporting answer keys
class AnswerKeyIOService {
  
  /// Import answer key from CSV format
  /// Expected formats:
  /// 1. Simple: "1,A\n2,B\n3,C" (question,answer per line)
  /// 2. With header: "Question,Answer\n1,A\n2,B"
  /// 3. Multi-answer: "1,A,B\n2,C\n3,A,D" (multiple correct answers)
  /// 4. Compact: "ABCDEABCDE..." (one letter per question, in order)
  static AnswerKeyImportResult importFromCsv(String csvContent) {
    final lines = csvContent.trim().split(RegExp(r'[\r\n]+'));
    if (lines.isEmpty) {
      return AnswerKeyImportResult.error('Empty file');
    }
    
    // Try to detect format
    final firstLine = lines.first.trim();
    
    // Check for compact format (just letters)
    if (RegExp(r'^[A-Ea-e]+$').hasMatch(firstLine) && lines.length == 1) {
      return _parseCompactFormat(firstLine);
    }
    
    // Check if first line is a header
    final hasHeader = firstLine.toLowerCase().contains('question') ||
                      firstLine.toLowerCase().contains('answer') ||
                      firstLine.toLowerCase().contains('key');
    
    final dataLines = hasHeader ? lines.skip(1).toList() : lines;
    
    return _parseCsvLines(dataLines);
  }
  
  /// Parse compact format: "ABCDEABCDE..."
  static AnswerKeyImportResult _parseCompactFormat(String letters) {
    final answers = <int, List<String>>{};
    final normalized = letters.toUpperCase();
    
    for (int i = 0; i < normalized.length; i++) {
      final letter = normalized[i];
      if ('ABCDE'.contains(letter)) {
        answers[i + 1] = [letter];
      } else {
        return AnswerKeyImportResult.error(
          'Invalid character "$letter" at position ${i + 1}. Only A-E allowed.'
        );
      }
    }
    
    return AnswerKeyImportResult.success(
      answers: answers,
      totalQuestions: answers.length,
      format: 'compact',
    );
  }
  
  /// Parse CSV lines: "1,A" or "1,A,B" format
  static AnswerKeyImportResult _parseCsvLines(List<String> lines) {
    final answers = <int, List<String>>{};
    final errors = <String>[];
    int maxQuestion = 0;
    
    for (int lineNum = 0; lineNum < lines.length; lineNum++) {
      final line = lines[lineNum].trim();
      if (line.isEmpty) continue;
      
      // Split by comma, semicolon, or tab
      final parts = line.split(RegExp(r'[,;\t]+')).map((p) => p.trim()).toList();
      
      if (parts.isEmpty) continue;
      
      // First part should be question number
      final questionNum = int.tryParse(parts[0]);
      if (questionNum == null || questionNum < 1) {
        // Maybe it's just answers without question numbers
        // Try to parse as answer-only format
        if (parts.every((p) => RegExp(r'^[A-Ea-e]$').hasMatch(p))) {
          final q = lineNum + 1;
          answers[q] = parts.map((p) => p.toUpperCase()).toList();
          if (q > maxQuestion) maxQuestion = q;
          continue;
        }
        errors.add('Line ${lineNum + 1}: Invalid question number "${parts[0]}"');
        continue;
      }
      
      // Rest should be answer letters
      final answerLetters = <String>[];
      for (int i = 1; i < parts.length; i++) {
        final letter = parts[i].toUpperCase();
        if (letter.isEmpty) continue;
        if (RegExp(r'^[A-E]$').hasMatch(letter)) {
          answerLetters.add(letter);
        } else {
          errors.add('Line ${lineNum + 1}: Invalid answer "$letter" for Q$questionNum');
        }
      }
      
      if (answerLetters.isNotEmpty) {
        answers[questionNum] = answerLetters;
        if (questionNum > maxQuestion) maxQuestion = questionNum;
      }
    }
    
    if (answers.isEmpty) {
      return AnswerKeyImportResult.error(
        errors.isNotEmpty 
            ? 'No valid answers found:\n${errors.take(5).join('\n')}'
            : 'No valid answers found in file'
      );
    }
    
    return AnswerKeyImportResult.success(
      answers: answers,
      totalQuestions: maxQuestion,
      format: 'csv',
      warnings: errors.isNotEmpty ? errors : null,
    );
  }
  
  /// Import from JSON format
  /// Expected: {"1": ["A"], "2": ["B", "C"], ...} or {"1": "A", "2": "B", ...}
  static AnswerKeyImportResult importFromJson(String jsonContent) {
    try {
      final decoded = jsonDecode(jsonContent);
      
      if (decoded is! Map) {
        return AnswerKeyImportResult.error('JSON must be an object');
      }
      
      final answers = <int, List<String>>{};
      int maxQuestion = 0;
      
      for (final entry in decoded.entries) {
        final questionNum = int.tryParse(entry.key.toString());
        if (questionNum == null || questionNum < 1) {
          continue;
        }
        
        List<String> answerList;
        if (entry.value is String) {
          answerList = [entry.value.toString().toUpperCase()];
        } else if (entry.value is List) {
          answerList = (entry.value as List)
              .map((v) => v.toString().toUpperCase())
              .where((v) => RegExp(r'^[A-E]$').hasMatch(v))
              .toList();
        } else {
          continue;
        }
        
        if (answerList.isNotEmpty) {
          answers[questionNum] = answerList;
          if (questionNum > maxQuestion) maxQuestion = questionNum;
        }
      }
      
      if (answers.isEmpty) {
        return AnswerKeyImportResult.error('No valid answers in JSON');
      }
      
      return AnswerKeyImportResult.success(
        answers: answers,
        totalQuestions: maxQuestion,
        format: 'json',
      );
    } catch (e) {
      return AnswerKeyImportResult.error('Invalid JSON: $e');
    }
  }
  
  /// Export answer key to CSV format
  static String exportToCsv(Map<int, List<String>> answerKey, {bool includeHeader = true}) {
    final buffer = StringBuffer();
    
    if (includeHeader) {
      buffer.writeln('Question,Answer');
    }
    
    final sortedKeys = answerKey.keys.toList()..sort();
    for (final q in sortedKeys) {
      final answers = answerKey[q] ?? [];
      if (answers.isNotEmpty) {
        buffer.writeln('$q,${answers.join(",")}');
      }
    }
    
    return buffer.toString();
  }
  
  /// Export answer key to compact format (just letters)
  static String exportToCompact(Map<int, List<String>> answerKey, int totalQuestions) {
    final buffer = StringBuffer();
    
    for (int q = 1; q <= totalQuestions; q++) {
      final answers = answerKey[q];
      if (answers != null && answers.isNotEmpty) {
        buffer.write(answers.first); // Only first answer in compact format
      } else {
        buffer.write('?'); // Unanswered question marker
      }
    }
    
    return buffer.toString();
  }
  
  /// Export answer key to JSON format
  static String exportToJson(Map<int, List<String>> answerKey, {bool prettyPrint = true}) {
    final Map<String, dynamic> jsonMap = {};
    
    final sortedKeys = answerKey.keys.toList()..sort();
    for (final q in sortedKeys) {
      final answers = answerKey[q] ?? [];
      if (answers.isNotEmpty) {
        jsonMap['$q'] = answers.length == 1 ? answers.first : answers;
      }
    }
    
    if (prettyPrint) {
      return const JsonEncoder.withIndent('  ').convert(jsonMap);
    }
    return jsonEncode(jsonMap);
  }
  
  /// Auto-detect format and import
  static AnswerKeyImportResult autoImport(String content) {
    final trimmed = content.trim();
    
    // Try JSON first (starts with { or [)
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final result = importFromJson(trimmed);
      if (result.success) return result;
    }
    
    // Try CSV/text format
    return importFromCsv(trimmed);
  }
}

/// Result of answer key import operation
class AnswerKeyImportResult {
  final bool success;
  final Map<int, List<String>>? answers;
  final int? totalQuestions;
  final String? format;
  final String? errorMessage;
  final List<String>? warnings;
  
  AnswerKeyImportResult._({
    required this.success,
    this.answers,
    this.totalQuestions,
    this.format,
    this.errorMessage,
    this.warnings,
  });
  
  factory AnswerKeyImportResult.success({
    required Map<int, List<String>> answers,
    required int totalQuestions,
    required String format,
    List<String>? warnings,
  }) {
    return AnswerKeyImportResult._(
      success: true,
      answers: answers,
      totalQuestions: totalQuestions,
      format: format,
      warnings: warnings,
    );
  }
  
  factory AnswerKeyImportResult.error(String message) {
    return AnswerKeyImportResult._(
      success: false,
      errorMessage: message,
    );
  }
  
  @override
  String toString() {
    if (success) {
      return 'AnswerKeyImportResult(success, ${answers?.length} questions, format: $format)';
    }
    return 'AnswerKeyImportResult(error: $errorMessage)';
  }
}

/// Answer key template for saving/loading presets
class AnswerKeyTemplate {
  final String id;
  final String name;
  final String? description;
  final Map<int, List<String>> answerKey;
  final int totalQuestions;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  
  AnswerKeyTemplate({
    required this.id,
    required this.name,
    this.description,
    required this.answerKey,
    required this.totalQuestions,
    required this.createdAt,
    this.lastUsedAt,
  });
  
  factory AnswerKeyTemplate.create({
    required String name,
    String? description,
    required Map<int, List<String>> answerKey,
    required int totalQuestions,
  }) {
    return AnswerKeyTemplate(
      id: 'tpl_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      description: description,
      answerKey: Map.from(answerKey),
      totalQuestions: totalQuestions,
      createdAt: DateTime.now(),
    );
  }
  
  AnswerKeyTemplate copyWith({
    String? name,
    String? description,
    Map<int, List<String>>? answerKey,
    int? totalQuestions,
    DateTime? lastUsedAt,
  }) {
    return AnswerKeyTemplate(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      answerKey: answerKey ?? Map.from(this.answerKey),
      totalQuestions: totalQuestions ?? this.totalQuestions,
      createdAt: createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'answerKey': answerKey.map((k, v) => MapEntry('$k', v)),
      'totalQuestions': totalQuestions,
      'createdAt': createdAt.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
    };
  }
  
  factory AnswerKeyTemplate.fromJson(Map<String, dynamic> json) {
    final rawAnswerKey = json['answerKey'] as Map<String, dynamic>? ?? {};
    final answerKey = <int, List<String>>{};
    
    rawAnswerKey.forEach((key, value) {
      final q = int.tryParse(key);
      if (q != null && value is List) {
        answerKey[q] = value.map((v) => v.toString()).toList();
      }
    });
    
    return AnswerKeyTemplate(
      id: json['id'] as String? ?? 'tpl_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Unnamed Template',
      description: json['description'] as String?,
      answerKey: answerKey,
      totalQuestions: json['totalQuestions'] as int? ?? answerKey.length,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
      lastUsedAt: json['lastUsedAt'] != null 
          ? DateTime.tryParse(json['lastUsedAt'] as String)
          : null,
    );
  }
}

/// Global list of saved answer key templates
List<AnswerKeyTemplate> globalAnswerKeyTemplates = [];
