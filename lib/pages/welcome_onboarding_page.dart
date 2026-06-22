import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_text_styles.dart';
import 'package:omr_app/widgets/app_primary_button.dart';
import 'package:omr_app/widgets/auth_shell.dart';

class WelcomeOnboardingPage extends StatefulWidget {
  const WelcomeOnboardingPage({
    super.key,
    this.teacherName,
    required this.onFinished,
    this.reviewMode = false,
  });

  final String? teacherName;
  final VoidCallback onFinished;
  final bool reviewMode;

  @override
  State<WelcomeOnboardingPage> createState() => _WelcomeOnboardingPageState();
}

class _WelcomeOnboardingPageState extends State<WelcomeOnboardingPage> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  static const _slides = <_OnboardingSlide>[
    _OnboardingSlide(
      icon: Icons.upload_file_rounded,
      title: 'Import your roster',
      body:
          'Load students from Excel or CSV. The app assigns OMR IDs and organizes them by section.',
    ),
    _OnboardingSlide(
      icon: Icons.edit_note_rounded,
      title: 'Create an answer key',
      body:
          'Add your subject, set the correct answers, and print answer sheets for the class.',
    ),
    _OnboardingSlide(
      icon: Icons.qr_code_scanner_rounded,
      title: 'Scan answer sheets',
      body:
          'Use your phone camera to grade sheets. Low-confidence scans go to a review queue you can fix.',
    ),
    _OnboardingSlide(
      icon: Icons.assessment_rounded,
      title: 'Export results',
      body:
          'Share CSV/PDF scores, exam summaries, and item analysis — even when you are offline.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_pageIndex >= _slides.length) {
      widget.onFinished();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final greetingName = widget.teacherName?.trim();
    final isWelcomePage = _pageIndex == 0;

    return Scaffold(
      backgroundColor: AppColors.appCanvas,
      appBar: widget.reviewMode
          ? AppBar(
              backgroundColor: AppColors.appCanvas,
              elevation: 0,
              foregroundColor: AppColors.brandText,
              title: const Text(
                'How it works',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (index) => setState(() => _pageIndex = index),
                children: [
                  _buildWelcomePage(greetingName),
                  ..._slides.map(_buildStepPage),
                ],
              ),
            ),
            _buildFooter(isWelcomePage),
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomePage(String? greetingName) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
      child: Column(
        children: [
          const CocSealLogo(size: 88),
          const SizedBox(height: 24),
          Text(
            greetingName != null && greetingName.isNotEmpty
                ? 'Welcome, $greetingName!'
                : 'Welcome to COC OMR',
            textAlign: TextAlign.center,
            style: AppTextStyles.pageTitle.copyWith(fontSize: 26),
          ),
          const SizedBox(height: 12),
          const Text(
            'Grade exams from your phone — offline on exam day, with optional cloud backup when you are online.',
            textAlign: TextAlign.center,
            style: AppTextStyles.pageSubtitle,
          ),
          const SizedBox(height: 28),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.brandBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.reviewMode ? 'Quick overview' : 'Before your first exam',
                  style: AppTextStyles.sectionLabel,
                ),
                const SizedBox(height: 12),
                for (var i = 0; i < _slides.length; i++) ...[
                  if (i > 0) const SizedBox(height: 10),
                  _WelcomeStepPreview(
                    number: i + 1,
                    title: _slides[i].title,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepPage(_OnboardingSlide slide) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 12),
      child: Column(
        children: [
          const Spacer(),
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: AppColors.brandGreen.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(slide.icon, size: 42, color: AppColors.brandGreenDark),
          ),
          const SizedBox(height: 28),
          Text(
            slide.title,
            textAlign: TextAlign.center,
            style: AppTextStyles.pageTitle.copyWith(fontSize: 24),
          ),
          const SizedBox(height: 14),
          Text(
            slide.body,
            textAlign: TextAlign.center,
            style: AppTextStyles.pageSubtitle.copyWith(fontSize: 15),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }

  Widget _buildFooter(bool isWelcomePage) {
    final totalPages = _slides.length + 1;
    final isLastPage = _pageIndex == totalPages - 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(totalPages, (index) {
              final active = index == _pageIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 22 : 8,
                height: 8,
                decoration: BoxDecoration(
                  color: active
                      ? AppColors.brandGreen
                      : AppColors.brandBorder,
                  borderRadius: BorderRadius.circular(999),
                ),
              );
            }),
          ),
          const SizedBox(height: 20),
          AppPrimaryButton(
            label: isLastPage
                ? (widget.reviewMode ? 'Close' : 'Go to dashboard')
                : (isWelcomePage ? 'Show me how' : 'Next'),
            onPressed: isLastPage ? widget.onFinished : _goNext,
          ),
          if (!widget.reviewMode && _pageIndex < totalPages - 1) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onFinished,
              child: const Text('Skip for now'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OnboardingSlide {
  const _OnboardingSlide({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;
}

class _WelcomeStepPreview extends StatelessWidget {
  const _WelcomeStepPreview({
    required this.number,
    required this.title,
  });

  final int number;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.brandGreen.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: AppColors.brandGreenDark,
              fontSize: 13,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: AppColors.brandText,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
