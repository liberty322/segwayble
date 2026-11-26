import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/logger.dart';
import 'screens/scan_screen.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  talker.info('App started');
  runApp(const ProviderScope(child: SegwayApp()));
}

class SegwayApp extends StatelessWidget {
  const SegwayApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Segway BLE',
      theme: AppTheme.dark,
      home: const ScanScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
