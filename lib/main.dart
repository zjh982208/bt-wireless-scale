import 'package:flutter/material.dart';

import 'app/scale_controller.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = ScaleController();
  await controller.init();
  runApp(SdWirelessScaleApp(controller: controller));
}

class SdWirelessScaleApp extends StatelessWidget {
  const SdWirelessScaleApp({super.key, required this.controller});

  final ScaleController controller;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SD\u65e0\u7ebf\u79e4',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1A73E8)),
        useMaterial3: true,
      ),
      home: HomePage(controller: controller),
    );
  }
}
