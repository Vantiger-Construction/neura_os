import 'dart:convert';
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
import 'package:neuro_companion/services/neura_companion_presence.dart';
import 'package:neuro_companion/src/shell/shell_prefs.dart';
import 'package:neuro_companion/core/neura_events_extra.dart';
import 'package:neuro_companion/avatar/motion/neura_motion_engine.dart';

final captureKey = GlobalKey();
final phase = ValueNotifier(NeuraPresencePhase.idle);
final prefs = ShellPrefsController.instance.prefs;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AvatarGlobals.service.selectedAvatarId.value = AvatarRegistry.nebulaId;
  NeuraMotion.instance.start();
  runApp(MaterialApp(theme: AppTheme.dark(), home: Scaffold(
    body: RepaintBoundary(key: captureKey, child: AnimatedBuilder(
      animation: Listenable.merge([phase, prefs]),
      builder: (context, _) => PresenceNavigationShell(
        currentIndex: 0, onDestinationSelected: (_) {},
        destinationPages: List<Widget>.filled(5, const SizedBox.shrink()),
        commands: const [],
        preferences: prefs.value,
        status: PresenceShellStatus(safeMode: phase.value == NeuraPresencePhase.safeMode, cloudLabel: 'Off',
          voiceLabel: 'Off', presenceLabel: phase.value.name, phase: phase.value),
        now: const SizedBox.shrink(), onOpenNeura: () {}, onOpenDiagnostics: () {},
      ),
    )),
  )));
  try {
    final output = Directory(Platform.environment['NEURA_POSE_OUTPUT']!);
    final records = <String, Object>{};
    Future<void> capture(String name) async {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final view = WidgetsBinding.instance.platformDispatcher.views.first;
      records[name] = {'width': boundary.size.width, 'height': boundary.size.height, 'devicePixelRatio': view.devicePixelRatio};
      final frame = await boundary.toImage(pixelRatio: 1);
      try {
        final bytes = (await frame.toByteData(format: ui.ImageByteFormat.png))!;
        await File('${output.path}/$name.png').writeAsBytes(bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes), flush: true);
      } finally {
        frame.dispose();
      }
    }
    Future<void> observe(String name) async {
      await Future<void>.delayed(const Duration(milliseconds: 750));
      await capture(name);
    }
    await Future<void>.delayed(const Duration(seconds: 2));
    await capture('idle');
    final ctl = AvatarGlobals.controller;
    ctl.setListening(true);
    NeuraMotion.instance.engine.setPhase(NeuraBodyPhase.listening);
    phase.value = NeuraPresencePhase.listening;
    await observe('listening');
    ctl.setListening(false);
    ctl.setTalking(true);
    ctl.setNumberInput('viseme', NeuraViseme.AI.index.toDouble());
    ctl.setNumberInput('mouthOpen', 0.6);
    NeuraMotion.instance.engine.setPhase(NeuraBodyPhase.speaking);
    phase.value = NeuraPresencePhase.speaking;
    await observe('speaking');
    ctl.setTalking(false);
    NeuraMotion.instance.engine.setPhase(NeuraBodyPhase.idle);
    phase.value = NeuraPresencePhase.idle;
    await observe('returned-idle');
    prefs.value = prefs.value.copyWith(companionMotion: NeuraCompanionMotion.still);
    await observe('still-first');
    await observe('still-later');
    prefs.value = prefs.value.copyWith(companionMotion: NeuraCompanionMotion.subtle);
    await observe('resumed');
    await File('${output.path}/resize-request').writeAsString('ready', flush: true);
    final ack = File('${output.path}/resize-complete');
    for (var i = 0; i < 90 && !await ack.exists(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    if (!await ack.exists()) throw StateError('Native resize was not acknowledged.');
    await observe('restored-narrow');
    if ((captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary).size.width >= 960) {
      throw StateError('Compact breakpoint was not reached.');
    }
    SafeBoot.instance.safeMode.value = true;
    phase.value = NeuraPresencePhase.safeMode;
    await observe('narrow-safe-mode');
    await File('${output.path}/measurements.json').writeAsString(jsonEncode(records), flush: true);
    exit(0);
  } catch (error, stack) {
    stderr.writeln('$error\n$stack');
    exit(1);
  }
}
