import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/cloud_sync_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/sync_preferences_service.dart';

/// Live sync state for dashboard UI and other listeners.
class AutoSyncSnapshot {
  const AutoSyncSnapshot({
    required this.pendingCount,
    required this.isSyncing,
    this.lastSyncAt,
    this.lastPushSummary,
  });

  final int pendingCount;
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final SyncSummary? lastPushSummary;

  AutoSyncSnapshot copyWith({
    int? pendingCount,
    bool? isSyncing,
    DateTime? lastSyncAt,
    SyncSummary? lastPushSummary,
  }) {
    return AutoSyncSnapshot(
      pendingCount: pendingCount ?? this.pendingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      lastPushSummary: lastPushSummary ?? this.lastPushSummary,
    );
  }
}

/// Uploads pending roster and score changes as soon as Wi-Fi is available.
///
/// Runs app-wide so scans sync even when the teacher is not on the dashboard.
class AutoSyncService with WidgetsBindingObserver {
  AutoSyncService._();

  static final AutoSyncService instance = AutoSyncService._();

  static const Duration _debounceAfterLocalChange = Duration(milliseconds: 600);

  final StreamController<AutoSyncSnapshot> _snapshotController =
      StreamController<AutoSyncSnapshot>.broadcast();

  Stream<AutoSyncSnapshot> get snapshots => _snapshotController.stream;

  AutoSyncSnapshot _snapshot = const AutoSyncSnapshot(
    pendingCount: 0,
    isSyncing: false,
  );

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  Timer? _debounceTimer;
  bool _started = false;
  bool _syncInProgress = false;
  bool _syncAgain = false;
  bool _wasOffline = false;
  bool _listeningForLocalWrites = false;

  AutoSyncSnapshot get currentSnapshot => _snapshot;

  Future<void> start() async {
    if (_started) {
      return;
    }
    _started = true;

    WidgetsBinding.instance.addObserver(this);

    _listeningForLocalWrites = true;
    onLocalDataPersisted = () => scheduleSync();

    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    _wasOffline = !_hasNetworkConnection(initial);

    if (_hasNetworkConnection(initial)) {
      scheduleSync(immediate: true);
    }

    _connectivitySub = connectivity.onConnectivityChanged.listen((results) {
      final isOnline = _hasNetworkConnection(results);
      if (isOnline && _wasOffline) {
        scheduleSync(immediate: true);
      }
      _wasOffline = !isOnline;
    });

    unawaited(_refreshPendingCount());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      scheduleSync(immediate: true);
    }
  }

  /// Debounced unless [immediate] is true (connectivity restore, app resume).
  void scheduleSync({bool immediate = false}) {
    _debounceTimer?.cancel();
    if (immediate) {
      unawaited(_maybeSync());
      return;
    }
    _debounceTimer = Timer(_debounceAfterLocalChange, () {
      unawaited(_maybeSync());
    });
  }

  Future<FullSyncSummary?> syncNow() async {
    if (!ApiService.hasActiveSession) {
      throw const SyncException('Sign in online to sync your data to the cloud.');
    }
    if (_syncInProgress) {
      _syncAgain = true;
      return null;
    }

    _syncInProgress = true;
    _emit(isSyncing: true);
    try {
      final summary = await CloudSyncService.instance.syncAll();
      await LocalDataStore.instance.reloadFromDatabase();
      final lastSyncAt = await SyncPreferencesService.getLastSyncAt();
      await _refreshPendingCount(
        isSyncing: false,
        lastSyncAt: lastSyncAt,
        lastPushSummary: summary.push,
      );
      return summary;
    } catch (error) {
      _emit(isSyncing: false);
      rethrow;
    } finally {
      _syncInProgress = false;
      if (_syncAgain) {
        _syncAgain = false;
        scheduleSync(immediate: true);
      }
    }
  }

  Future<void> _maybeSync() async {
    if (_syncInProgress ||
        !ApiService.isReady ||
        !ApiService.hasActiveSession) {
      return;
    }

    if (!await SyncPreferencesService.getAutoSyncOnWifi()) {
      await _refreshPendingCount();
      return;
    }

    final results = await Connectivity().checkConnectivity();
    if (!_hasNetworkConnection(results)) {
      return;
    }
    if (!_isWifiLikeConnection(results)) {
      await _refreshPendingCount();
      return;
    }

    final pending = await LocalDataStore.instance.countPendingSync();
    if (pending == 0) {
      await _refreshPendingCount(pendingCount: 0);
      return;
    }

    try {
      await syncNow();
    } catch (error) {
      debugPrint('Auto-sync failed: $error');
    }
  }

  Future<void> _refreshPendingCount({
    int? pendingCount,
    bool? isSyncing,
    DateTime? lastSyncAt,
    SyncSummary? lastPushSummary,
  }) async {
    final pending =
        pendingCount ?? await LocalDataStore.instance.countPendingSync();
    _emit(
      pendingCount: pending,
      isSyncing: isSyncing,
      lastSyncAt: lastSyncAt,
      lastPushSummary: lastPushSummary,
    );
  }

  void _emit({
    int? pendingCount,
    bool? isSyncing,
    DateTime? lastSyncAt,
    SyncSummary? lastPushSummary,
  }) {
    _snapshot = _snapshot.copyWith(
      pendingCount: pendingCount,
      isSyncing: isSyncing,
      lastSyncAt: lastSyncAt,
      lastPushSummary: lastPushSummary,
    );
    if (!_snapshotController.isClosed) {
      _snapshotController.add(_snapshot);
    }
  }

  bool _hasNetworkConnection(List<ConnectivityResult> results) {
    return results.any((result) => result != ConnectivityResult.none);
  }

  bool _isWifiLikeConnection(List<ConnectivityResult> results) {
    return results.any(
      (result) =>
          result == ConnectivityResult.wifi ||
          result == ConnectivityResult.ethernet,
    );
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _debounceTimer?.cancel();
    _snapshotController.close();
    if (_listeningForLocalWrites) {
      onLocalDataPersisted = null;
      _listeningForLocalWrites = false;
    }
  }
}
