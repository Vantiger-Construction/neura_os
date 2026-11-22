import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:neuro_companion/avatar/avatar_globals.dart';
import 'package:neuro_companion/avatar/avatar_registry.dart';
import 'package:neuro_companion/avatar/motion/neura_motion.dart';
import 'package:neuro_companion/modules/navigation/presence_navigation_shell.dart';
import 'package:neuro_companion/reliability/safe_boot.dart';
import 'package:neuro_companion/theme/app_theme.dart';

final captureKey = GlobalKey();
final safe = ValueNotifier(false);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AvatarGlobals.service.selectedAvatarId.value = AvatarRegistry.nebulaId;
  NeuraMotion.instance.start();
  runApp(MaterialApp(theme: AppTheme.dark(), home: Scaffold(
    body: RepaintBoundary(key: captureKey, child: ValueListenableBuilder<bool>(
      valueListenable: safe,
      builder: (context, inSafeMode, _) => PresenceNavigationShell(
        currentIndex: 0, onDestinationSelected: (_) {},
        destinationPages: List<Widget>.filled(5, const SizedBox.shrink()),
        commands: const [],
        status: PresenceShellStatus(safeMode: inSafeMode, cloudLabel: 'Off',
          voiceLabel: 'Off', presenceLabel: inSafeMode ? 'Safe Mode' : 'Idle'),
        now: const SizedBox.shrink(), onOpenNeura: () {}, onOpenDiagnostics: () {},
      ),
    )),
  )));
  try {
    final output = Directory(Platform.environment['NEURA_POSE_OUTPUT']!);
    Future<void> capture(String name) async {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final frame = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = (await frame.toByteData(format: ui.ImageByteFormat.png))!;
        await File('${output.path}/$name.png').writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
      } finally {
        frame.dispose();
      }
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await capture('idle-start');
    await Future<void>.delayed(const Duration(seconds: 30));
    await capture('idle-after-30s');
    SafeBoot.instance.safeMode.value = true;
    safe.value = true;
    await Future<void>.delayed(const Duration(seconds: 2));
    await capture('safe-mode');
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
