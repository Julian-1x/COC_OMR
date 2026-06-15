import 'package:flutter/material.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/app_card.dart';

class OmrIdListPage extends StatefulWidget {
  const OmrIdListPage({super.key});

  @override
  State<OmrIdListPage> createState() => _OmrIdListPageState();
}

class _OmrIdListPageState extends State<OmrIdListPage> {
  static const Color brandGreen = AppColors.brandGreen;
  static const Color brandSurface = AppColors.brandSurface;
  static const Color brandBorder = AppColors.brandBorder;
  static const Color brandText = AppColors.brandText;
  static const Color brandMuted = AppColors.brandMuted;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  List<Student> get _filteredStudents {
    final query = _searchQuery.trim().toLowerCase();
    final students = globalStudentDatabase.where((student) {
      if (query.isEmpty) {
        return true;
      }

      return student.omrId.toLowerCase().contains(query) ||
          student.name.toLowerCase().contains(query) ||
          student.schoolId.toLowerCase().contains(query) ||
          student.section.toLowerCase().contains(query);
    }).toList()
      ..sort((a, b) => a.omrId.compareTo(b.omrId));

    return students;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  ScanResult? _latestResultForStudent(Student student) {
    final results = findScansByStudent(student.omrId).toList()
      ..sort((a, b) => b.scanTime.compareTo(a.scanTime));

    return results.isEmpty ? null : results.first;
  }

  String _formatDate(DateTime date) {
    final hour = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final minute = date.minute.toString().padLeft(2, '0');
    final suffix = date.hour >= 12 ? 'PM' : 'AM';
    return '${date.month}/${date.day}/${date.year} $hour:$minute $suffix';
  }

  void _showStudentDetails(Student student) {
    final results = findScansByStudent(student.omrId).toList()
      ..sort((a, b) => b.scanTime.compareTo(a.scanTime));
    final latest = results.isEmpty ? null : results.first;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        minChildSize: 0.45,
        maxChildSize: 0.9,
        builder: (context, scrollController) => ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
          children: [
            Center(
              child: Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: brandBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: brandSurface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: brandBorder),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: brandGreen,
                    child: Text(
                      student.omrId,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          student.name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: brandText,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'School ID: ${student.schoolId}',
                          style: const TextStyle(
                            color: brandMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Section: ${student.section}',
                          style: const TextStyle(
                            color: brandMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: brandBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Latest Status',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: brandText,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    latest == null
                        ? 'No scan result yet'
                        : '${latest.subjectName} - ${latest.scoreDisplay}/${latest.totalQuestions} - ${latest.percentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: latest == null ? brandMuted : brandGreen,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (latest != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'Scanned ${_formatDate(latest.scanTime)}',
                      style: const TextStyle(color: brandMuted),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Scan History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: brandText,
              ),
            ),
            const SizedBox(height: 12),
            if (results.isEmpty)
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: brandBorder),
                ),
                child: const Text(
                  'This student does not have any scan records yet.',
                  style: TextStyle(color: brandMuted),
                ),
              )
            else
              ...results.map(
                (result) => Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: brandBorder),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              result.subjectName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: brandText,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${result.scoreDisplay}/${result.totalQuestions} - ${result.percentage.toStringAsFixed(1)}%',
                              style: const TextStyle(color: brandMuted),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatDate(result.scanTime),
                              style: const TextStyle(
                                color: brandMuted,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: result.passed
                              ? brandGreen.withValues(alpha: 0.12)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          result.passed ? 'Passed' : 'Needs Work',
                          style: TextStyle(
                            color: result.passed
                                ? brandGreen
                                : const Color(0xFFDC2626),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: 'Search OMR ID, name, school ID, or section',
        prefixIcon: const Icon(Icons.search_rounded),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.close_rounded),
              ),
      ),
    );
  }

  Widget _buildStudentTile(Student student) {
    final latest = _latestResultForStudent(student);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _showStudentDetails(student),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: brandBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: brandGreen,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    student.omrId,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: brandText,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'School ID: ${student.schoolId}',
                        style: const TextStyle(color: brandMuted),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Section: ${student.section}',
                        style: const TextStyle(color: brandMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: latest == null
                            ? const Color(0xFFFEF3C7)
                            : brandGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        latest == null ? 'Pending' : 'Scanned',
                        style: TextStyle(
                          color: latest == null
                              ? const Color(0xFFD97706)
                              : brandGreen,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: brandMuted,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filteredStudents = _filteredStudents;

    return Scaffold(
      appBar: AppBar(
        title: const Text('OMR ID List'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Search student OMR IDs',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: brandText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'View all imported students and search by OMR ID, name, school ID, or section.',
                  style: TextStyle(
                    color: brandMuted.withValues(alpha: 0.95),
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                _buildSearchField(),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _InfoChip(
                      label: 'Students',
                      value: '${globalStudentDatabase.length}',
                    ),
                    _InfoChip(
                      label: 'Matches',
                      value: '${filteredStudents.length}',
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (filteredStudents.isEmpty)
            AppCard(
              padding: const EdgeInsets.all(28),
              child: Column(
                children: [
                  Icon(
                    Icons.tag_rounded,
                    size: 52,
                    color: brandMuted.withValues(alpha: 0.55),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No OMR IDs found',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: brandText,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    globalStudentDatabase.isEmpty
                        ? 'Import students first to generate and view OMR IDs.'
                        : 'Try a different search term.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: brandMuted),
                  ),
                ],
              ),
            )
          else
            ...filteredStudents.map(_buildStudentTile),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _OmrIdListPageState.brandBorder),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
            color: _OmrIdListPageState.brandMuted,
            fontSize: 13,
          ),
          children: [
            TextSpan(text: '$label: '),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: _OmrIdListPageState.brandText,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
