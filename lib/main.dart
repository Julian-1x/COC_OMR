import 'package:flutter/material.dart';
import 'dart:async';
import 'package:omr_app/pages/login_page.dart';
import 'package:omr_app/services/crash_reporting_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/scanner_engine.dart';
import 'package:omr_app/services/device_scan_capability.dart';
import 'package:omr_app/services/sqlite_init.dart';
import 'package:omr_app/services/api_service.dart';
import 'package:omr_app/services/theme_service.dart';
import 'package:omr_app/models/exam_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ApiService.init();

  ensureSqliteForPlatform();

  await ThemeService.init();

  await LocalDataStore.instance.loadIntoMemory();

  rebuildStudentIndex();

  // Warm scan engine + device tier in parallel — ready before the teacher opens the camera.
  unawaited(ScannerEngine.warmUp());
  unawaited(DeviceScanCapability.warmUp());

  await CrashReportingService.initAndRun(() => runApp(const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'COC OMR',
      theme: ThemeService.getLightTheme(),
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(
              minScaleFactor: 0.85,
              maxScaleFactor: 1.35,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: const LoginPage(),
    );
  }
}
