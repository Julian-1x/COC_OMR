import 'package:flutter/foundation.dart';
import 'package:omr_app/models/exam_data.dart';
import 'package:omr_app/models/phone_archive_pack.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/archive_retention.dart';
import 'package:omr_app/services/cloud_sync_service.dart';
import 'package:omr_app/services/local_data_store.dart';

/// Soft-delete → local pack → upload to web → purge phone (1A + 2A).
class PhoneArchiveService {
  PhoneArchiveService._();

  static final PhoneArchiveService instance = PhoneArchiveService._();

  Future<List<PhoneArchivePack>> listPacks() async {
    await purgeExpiredLocalPacks();
    return LocalDataStore.instance.fetchPhoneArchivePacks();
  }

  /// Permanently remove phone archive packs older than [ArchiveRetention.months].
  Future<int> purgeExpiredLocalPacks() async {
    if (kIsWeb) {
      return 0;
    }
    final packs = await LocalDataStore.instance.fetchPhoneArchivePacks();
    var removed = 0;
    for (final pack in packs) {
      if (!ArchiveRetention.isExpired(pack.createdAt)) {
        continue;
      }
      try {
        // Queue cloud deletions when possible, then drop the local pack.
        await LocalDataStore.instance.permanentlyDeletePhoneArchivePack(pack.id);
        removed++;
      } catch (error) {
        debugPrint('Expired archive purge failed (${pack.id}): $error');
        try {
          await LocalDataStore.instance.deletePhoneArchivePack(pack.id);
          removed++;
        } catch (_) {}
      }
    }
    return removed;
  }

  Future<int> pendingCount() {
    return LocalDataStore.instance.phoneArchivePackCount();
  }

  Future<PhoneArchiveMoveSummary> archiveStudents(List<String> omrIds) {
    return LocalDataStore.instance.moveStudentsToPhoneArchive(omrIds);
  }

  Future<PhoneArchiveMoveSummary> archiveSection(
    String sectionName, {
    bool mirroredFromCloud = false,
  }) {
    return LocalDataStore.instance.moveSectionToPhoneArchive(
      sectionName,
      mirroredFromCloud: mirroredFromCloud,
    );
  }

  /// After a cloud pull: classes archived on the web leave the phone dashboard
  /// and land in Phone Archive for offline restore.
  Future<int> mirrorCloudArchivedSections(Iterable<String> sectionNames) async {
    var moved = 0;
    final seen = <String>{};
    for (final raw in sectionNames) {
      final name = raw.trim();
      if (name.isEmpty) {
        continue;
      }
      final key = name.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }
      try {
        await archiveSection(name, mirroredFromCloud: true);
        moved++;
      } catch (error) {
        // Already gone from active dashboard, or name mismatch — safe to skip.
        debugPrint('Cloud archive mirror skipped ($name): $error');
      }
    }
    return moved;
  }

  /// Drop local classes that were permanently deleted on the school server.
  Future<int> dropPermanentlyDeletedCloudSections({
    required Iterable<String> activeSectionNames,
    required Iterable<String> archivedSectionNames,
  }) async {
    final known = <String>{
      for (final name in activeSectionNames)
        if (name.trim().isNotEmpty) name.trim().toLowerCase(),
      for (final name in archivedSectionNames)
        if (name.trim().isNotEmpty) name.trim().toLowerCase(),
    };

    var removed = 0;
    final localSections = List<Section>.from(globalSections);
    for (final section in localSections) {
      final key = section.name.trim().toLowerCase();
      if (key.isEmpty || known.contains(key)) {
        continue;
      }
      // Keep brand-new local-only classes that never reached the cloud.
      final syncedToCloud =
          section.cloudId != null && section.cloudId!.trim().isNotEmpty;
      if (!syncedToCloud) {
        continue;
      }
      try {
        await LocalDataStore.instance.archiveSectionLocally(section.name);
        removed++;
      } catch (error) {
        debugPrint('Cloud permanent-delete drop skipped (${section.name}): $error');
      }
    }

    // Also drop mirrored packs for sections no longer on the server.
    final packs = await listPacks();
    for (final pack in packs) {
      if (!pack.mirroredFromCloud || pack.kind != PhoneArchivePack.kindSection) {
        continue;
      }
      final packName = (pack.section?.name ??
              (pack.sectionNames.isNotEmpty ? pack.sectionNames.first : ''))
          .trim()
          .toLowerCase();
      if (packName.isEmpty || known.contains(packName)) {
        continue;
      }
      try {
        await LocalDataStore.instance.deletePhoneArchivePack(pack.id);
      } catch (error) {
        debugPrint('Cloud deleted pack cleanup skipped (${pack.id}): $error');
      }
    }

    return removed;
  }

  Future<void> restoreLocally(String packId) {
    return LocalDataStore.instance.restorePhoneArchivePack(packId);
  }

  Future<void> deleteForever(String packId) {
    return LocalDataStore.instance.permanentlyDeletePhoneArchivePack(packId);
  }

  /// Upload each local pack to the cloud as archived, then delete the pack
  /// from the phone to free storage.
  Future<int> uploadAndPurge({bool requireOnline = true}) async {
    if (kIsWeb) {
      return 0;
    }
    if (!ApiService.hasActiveSession) {
      if (requireOnline) {
        throw const SyncException(
          'Sign in while online to move Phone Archive to the web and free storage.',
        );
      }
      return 0;
    }

    final packs = await listPacks();
    if (packs.isEmpty) {
      return 0;
    }

    var purged = 0;
    for (final pack in packs) {
      // Already archived on the web — keep the pack on the phone for restore.
      if (pack.mirroredFromCloud) {
        continue;
      }
      try {
        await _uploadPack(pack);
        await LocalDataStore.instance.deletePhoneArchivePack(pack.id);
        purged++;
      } catch (error) {
        debugPrint('Phone archive upload failed (${pack.id}): $error');
      }
    }
    return purged;
  }

  Future<void> _uploadPack(PhoneArchivePack pack) async {
    if (pack.kind == PhoneArchivePack.kindSection) {
      final name = pack.section?.name ?? pack.sectionNames.first;
      await CloudSyncService.instance.markSectionArchivedOnCloud(
        sectionName: name,
        schoolYear: pack.section?.schoolYear,
        termLabel: pack.section?.termLabel,
      );
      return;
    }

    await ApiService.patchJson('/sync/students/archive', <String, dynamic>{
      'omr_ids': pack.omrIds,
    });
  }
}
