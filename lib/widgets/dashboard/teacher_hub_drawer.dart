import 'package:flutter/material.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/widgets/auth_shell.dart';

/// Sidebar: teacher identity, workspace snapshot, and global actions (not tab nav).
class TeacherHubDrawer extends StatefulWidget {
  const TeacherHubDrawer({
    super.key,
    required this.teacherName,
    required this.school,
    this.email,
    required this.isOnline,
    required this.hasCloudSession,
    required this.studentCount,
    required this.scannedCount,
    required this.pendingCount,
    required this.reviewCount,
    required this.pendingSyncCount,
    required this.isSyncing,
    required this.appVersion,
    required this.onScan,
    required this.onReview,
    required this.onSync,
    required this.onHelp,
    required this.onSignOut,
  });

  final String teacherName;
  final String school;
  final String? email;
  final bool isOnline;
  final bool hasCloudSession;
  final int studentCount;
  final int scannedCount;
  final int pendingCount;
  final int reviewCount;
  final int pendingSyncCount;
  final bool isSyncing;
  final String appVersion;
  final VoidCallback onScan;
  final VoidCallback onReview;
  final VoidCallback onSync;
  final VoidCallback onHelp;
  final VoidCallback onSignOut;

  @override
  State<TeacherHubDrawer> createState() => _TeacherHubDrawerState();
}

class _TeacherHubDrawerState extends State<TeacherHubDrawer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Animation<double> _fade(int index, {int stepMs = 70}) {
    final start = (index * stepMs) / 420;
    final end = ((index * stepMs) + 180) / 420;
    return CurvedAnimation(
      parent: _controller,
      curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0),
          curve: Curves.easeOutCubic),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            FadeTransition(
              opacity: _fade(0),
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.06),
                  end: Offset.zero,
                ).animate(_fade(0)),
                child: _buildHeader(),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fade(1),
              child: _buildSnapshot(),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: FadeTransition(
                opacity: _fade(2),
                child: const Text(
                  'Quick actions',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: AppColors.brandMuted,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fade(3),
              child: _HubActionTile(
                icon: Icons.document_scanner_rounded,
                label: 'Start scanning',
                subtitle: 'Pick a subject and scan sheets',
                color: AppColors.brandGreen,
                onTap: widget.onScan,
              ),
            ),
            if (widget.reviewCount > 0)
              FadeTransition(
                opacity: _fade(4),
                child: _HubActionTile(
                  icon: Icons.fact_check_rounded,
                  label: 'Review scans',
                  subtitle:
                      '${widget.reviewCount} need${widget.reviewCount == 1 ? 's' : ''} a manual check',
                  color: const Color(0xFFD97706),
                  onTap: widget.onReview,
                ),
              ),
            if (widget.pendingSyncCount > 0 || widget.hasCloudSession)
              FadeTransition(
                opacity: _fade(5),
                child: _HubActionTile(
                  icon: Icons.cloud_upload_rounded,
                  label: widget.isSyncing ? 'Syncing…' : 'Sync now',
                  subtitle: widget.pendingSyncCount > 0
                      ? '${widget.pendingSyncCount} item${widget.pendingSyncCount == 1 ? '' : 's'} waiting'
                      : 'Upload to cloud backup',
                  color: AppColors.brandGreenDark,
                  onTap: widget.isSyncing ? null : widget.onSync,
                ),
              ),
            FadeTransition(
              opacity: _fade(6),
              child: _HubActionTile(
                icon: Icons.menu_book_rounded,
                label: 'How it works',
                subtitle: 'Quick guide for new teachers',
                color: AppColors.brandMuted,
                onTap: widget.onHelp,
              ),
            ),
            const SizedBox(height: 16),
            FadeTransition(
              opacity: _fade(7),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Text(
                  'Version ${widget.appVersion}',
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fade(8),
              child: const Divider(height: 1),
            ),
            FadeTransition(
              opacity: _fade(8),
              child: _HubActionTile(
                icon: Icons.logout_rounded,
                label: 'Sign out',
                subtitle: 'Return to login screen',
                color: AppColors.brandText,
                onTap: widget.onSignOut,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final statusLabel = !widget.isOnline
        ? 'No internet'
        : widget.hasCloudSession
            ? 'Signed in · online'
            : 'On this device · PIN';

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.brandGreenDark, AppColors.brandGreen],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: AppColors.brandGreenDark.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const CocSealLogo(size: 56),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.teacherName.trim().isEmpty
                      ? 'Teacher'
                      : widget.teacherName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  widget.school.trim().isEmpty ? 'COC OMR Hub' : widget.school,
                  style: const TextStyle(
                    color: Color(0xFFE8F8EC),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (widget.email != null && widget.email!.trim().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.email!,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    statusLabel,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSnapshot() {
    final reviewPart = widget.reviewCount > 0
        ? ' · ${widget.reviewCount} to review'
        : '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.brandSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.brandBorder),
        ),
        child: Text(
          widget.studentCount == 0
              ? 'No students yet — import a roster to begin.'
              : '${widget.studentCount} students · ${widget.scannedCount} scanned · ${widget.pendingCount} pending$reviewPart',
          style: const TextStyle(
            color: AppColors.brandText,
            fontSize: 13,
            height: 1.35,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _HubActionTile extends StatelessWidget {
  const _HubActionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            title: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color:
                    onTap == null ? AppColors.brandMuted : AppColors.brandText,
              ),
            ),
            subtitle: Text(
              subtitle,
              style: const TextStyle(
                color: AppColors.brandMuted,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
