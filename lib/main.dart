import 'package:flutter/material.dart';
import 'package:omr_app/pages/login_page.dart';
import 'package:omr_app/services/crash_reporting_service.dart';
import 'package:omr_app/services/local_data_store.dart';
import 'package:omr_app/services/sqlite_init.dart';
import 'package:omr_app/services/supabase_service.dart';
import 'package:omr_app/services/theme_service.dart';
import 'package:omr_app/models/exam_data.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SupabaseService.init();

  ensureSqliteForPlatform();

  await ThemeService.init();

  await LocalDataStore.instance.loadIntoMemory();

  rebuildStudentIndex();

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
