import 'package:flutter/foundation.dart';
import 'package:omr_app/models/phone_archive_pack.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/cloud_sync_service.dart';
import 'package:omr_app/services/local_data_store.dart';

/// Soft-delete → local pack → upload to web → purge phone (1A + 2A).
class PhoneArchiveService {
  PhoneArchiveService._();

  static final PhoneArchiveService instance = PhoneArchiveService._();

  Future<List<PhoneArchivePack>> listPacks() {
    return LocalDataStore.instance.fetchPhoneArchivePacks();
  }

  Future<int> pendingCount() {
    return LocalDataStore.instance.phoneArchivePackCount();
  }

  Future<PhoneArchiveMoveSummary> archiveStudents(List<String> omrIds) {
    return LocalDataStore.instance.moveStudentsToPhoneArchive(omrIds);
  }

  Future<PhoneArchiveMoveSummary> archiveSection(String sectionName) {
    return LocalDataStore.instance.moveSectionToPhoneArchive(sectionName);
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
