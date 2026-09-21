import 'package:flutter/material.dart';
import 'package:omr_app/models/phone_archive_pack.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/phone_archive_service.dart';
import 'package:omr_app/theme/app_colors.dart';
import 'package:omr_app/utils/user_error_messages.dart';

/// Local soft-deleted students/sections (with scores) until uploaded to web.
class PhoneArchivePage extends StatefulWidget {
  const PhoneArchivePage({super.key});

  @override
  State<PhoneArchivePage> createState() => _PhoneArchivePageState();
}

class _PhoneArchivePageState extends State<PhoneArchivePage> {
  List<PhoneArchivePack> _packs = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final packs = await PhoneArchiveService.instance.listPacks();
    if (!mounted) return;
    setState(() {
      _packs = packs;
      _loading = false;
    });
  }

  void _snack(String message, {Color? color}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color ?? AppColors.brandGreen,
      ),
    );
  }

  Future<void> _restore(PhoneArchivePack pack) async {
    setState(() => _busy = true);
    try {
      await PhoneArchiveService.instance.restoreLocally(pack.id);
      if (!mounted) return;
      _snack(
        'Restored "${pack.title}" to this phone. Sync when online so the web matches.',
      );
      await _reload();
    } catch (error) {
      if (mounted) {
        _snack(
          UserErrorMessages.friendlySaveError(error),
          color: AppColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteForever(PhoneArchivePack pack) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete forever?'),
        content: Text(
          'Permanently remove "${pack.title}" from this phone and the cloud. '
          'Scores cannot be recovered.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await PhoneArchiveService.instance.deleteForever(pack.id);
      if (!mounted) return;
      _snack('Deleted "${pack.title}" forever.', color: AppColors.error);
      await _reload();
    } catch (error) {
      if (mounted) {
        _snack(
          UserErrorMessages.friendlySaveError(error),
          color: AppColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _uploadAll() async {
    if (!ApiService.hasActiveSession) {
      _snack(
        'Sign in while online to move archive items to the web and free phone storage.',
        color: AppColors.warningAccent,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final purged = await PhoneArchiveService.instance.uploadAndPurge();
      if (!mounted) return;
      if (purged == 0) {
        _snack(
          'Nothing uploaded. Check your connection and try Sync Now.',
          color: AppColors.warningAccent,
        );
      } else {
        _snack(
          'Moved $purged item${purged == 1 ? '' : 's'} to the web and cleared phone storage. '
          'View history under Classes → Archived on the portal.',
        );
      }
      await _reload();
    } catch (error) {
      if (mounted) {
        _snack(
          UserErrorMessages.friendlySaveError(error),
          color: AppColors.error,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.appCanvas,
      appBar: AppBar(
        title: const Text('Phone Archive'),
        actions: [
          if (_packs.isNotEmpty)
            TextButton(
              onPressed: _busy ? null : _uploadAll,
              child: const Text('Upload & clear'),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _packs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.inventory_2_outlined,
                          size: 56,
                          color: AppColors.brandMuted,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Archive is empty',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'When you remove a student or class, it lands here with scores '
                          'so you can restore offline.\n\n'
                          'When you are online, Sync Now (or Upload & clear) moves items '
                          'to the web portal and frees phone storage.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.brandMuted),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.brandGreen.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.brandBorder),
                      ),
                      child: const Text(
                        'These items are only on this phone until you upload. '
                        'Restore works offline. After upload, restore from the web when online.',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.brandText,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ..._packs.map((pack) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          title: Text(
                            pack.title,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${pack.subtitle}\n'
                            'Saved ${_formatWhen(pack.createdAt)}',
                          ),
                          isThreeLine: true,
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                tooltip: 'Restore',
                                onPressed: _busy ? null : () => _restore(pack),
                                icon: const Icon(
                                  Icons.restore_rounded,
                                  color: AppColors.brandGreen,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Delete forever',
                                onPressed:
                                    _busy ? null : () => _deleteForever(pack),
                                icon: const Icon(
                                  Icons.delete_forever_rounded,
                                  color: AppColors.error,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
    );
  }

  String _formatWhen(DateTime when) {
    final local = when.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
