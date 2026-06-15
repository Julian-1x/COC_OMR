import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

bool _sqliteDesktopInitialized = false;

/// Use native SQLite on Android/iOS; FFI on Windows/macOS/Linux so the same
/// code path works in development and release on desktop.
void ensureSqliteForPlatform() {
  if (kIsWeb) {
    return;
  }
  if (_sqliteDesktopInitialized) {
    return;
  }
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  _sqliteDesktopInitialized = true;
}
