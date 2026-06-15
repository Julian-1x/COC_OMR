import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_text_styles.dart';

class DashboardToolSection extends StatelessWidget {
  const DashboardToolSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(title, style: AppTextStyles.sectionLabel),
        ),
        ...children,
      ],
    );
  }
}
