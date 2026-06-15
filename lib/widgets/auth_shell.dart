import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/theme/app_spacing.dart';
import 'package:omr_app/widgets/app_card.dart';

enum AuthBadgeType { none, offline, online }

class CocSealLogo extends StatelessWidget {
  const CocSealLogo({
    super.key,
    this.size = 72,
    this.elevation = 8,
  });

  final double size;
  final double elevation;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: elevation,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/coc_seal.png',
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(
            Icons.school_rounded,
            color: AppColors.brandGreen,
          ),
        ),
      ),
    );
  }
}

class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.subtitle,
    required this.child,
    this.teacherName,
    this.schoolName,
    this.badge = AuthBadgeType.none,
    this.showLogo = true,
    this.compact = false,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final String? teacherName;
  final String? schoolName;
  final AuthBadgeType badge;
  final bool showLogo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(),
        SizedBox(height: compact ? AppSpacing.md : AppSpacing.lg),
        AppCard(
          padding: EdgeInsets.all(
            compact ? AppSpacing.md : AppSpacing.xl,
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final headerPadding = compact
        ? const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.md,
            AppSpacing.lg,
          )
        : const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xl,
            AppSpacing.xxl,
          );

    return Container(
      width: double.infinity,
      padding: headerPadding,
      decoration: BoxDecoration(
        gradient: AppColors.authHeaderGradient,
        borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreenDark.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          if (showLogo && !compact) ...[
            const CocSealLogo(size: 80),
            const SizedBox(height: AppSpacing.md),
          ],
          if (_badgeLabel != null) ...[
            _buildBadge(),
            const SizedBox(height: AppSpacing.sm),
          ],
          Text(
            teacherName != null ? 'Welcome back, $teacherName' : title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white,
              fontSize: compact ? 18 : 22,
              fontWeight: FontWeight.w800,
              height: 1.2,
            ),
          ),
          if (teacherName != null) ...[
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.88),
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (schoolName != null && schoolName!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              schoolName!,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.78),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.85),
              fontSize: 13,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  String? get _badgeLabel {
    switch (badge) {
      case AuthBadgeType.offline:
        return 'Offline mode';
      case AuthBadgeType.online:
        return 'Online sign-in';
      case AuthBadgeType.none:
        return null;
    }
  }

  IconData get _badgeIcon {
    switch (badge) {
      case AuthBadgeType.offline:
        return Icons.wifi_off_rounded;
      case AuthBadgeType.online:
        return Icons.cloud_done_rounded;
      case AuthBadgeType.none:
        return Icons.info_outline_rounded;
    }
  }

  Widget _buildBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_badgeIcon, color: Colors.white, size: 16),
          const SizedBox(width: 6),
          Text(
            _badgeLabel!,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class AuthLoadingShell extends StatelessWidget {
  const AuthLoadingShell({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CocSealLogo(size: 112),
        const SizedBox(height: AppSpacing.lg),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            color: AppColors.brandGreen,
            strokeWidth: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        const Text(
          'Loading COC OMR Hub...',
          style: TextStyle(
            color: AppColors.brandMuted,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Cagayan de Oro College',
          style: TextStyle(
            color: AppColors.brandMuted,
            fontSize: 12,
          ),
        ),
      ],
    );
  }
}
