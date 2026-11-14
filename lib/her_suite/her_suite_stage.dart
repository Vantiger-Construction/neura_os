import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../avatar/neura_avatar_runtime_bridge.dart';
import '../neura_shell/models/neura_room.dart';
import '../neura_shell/widgets/neura_room_presence_avatar.dart';
import '../services/neura_companion_presence.dart';
import '../src/shell/shell_prefs.dart';

/// Draws whatever sits on the stage behind the glass panels.
///
/// Today that is the Flutter avatar. When the Unity renderer takes over, pass
/// a builder that hosts the Unity window instead; Unity reads the same stage
/// values from the presence bridge, so the panels need no changes.
typedef HerSuiteStageBuilder = Widget Function(
  BuildContext context,
  NeuraStagePresentation stage,
);

/// Her Suite's lighting moods, matching the Unity palette in
/// `prototypes/unity-presence/Assets/Presence/Core/StageLook.cs`.
class HerSuiteMood {
  const HerSuiteMood._(this.label, this.background, this.accent);

  final String label;
  final Color background;
  final Color accent;

  /// In Her Suite, standard lighting is her gold hour.
  static HerSuiteMood of(NeuraStageLighting lighting) => switch (lighting) {
        NeuraStageLighting.standard || NeuraStageLighting.gold => gold,
        NeuraStageLighting.aurora => aurora,
        NeuraStageLighting.dusk => dusk,
      };

  static const gold =
      HerSuiteMood._('Gold hour', Color(0xFF0F0B08), Color(0xFFFFC94D));
  static const aurora =
      HerSuiteMood._('Aurora', Color(0xFF050D12), Color(0xFF80E6FF));
  static const dusk =
      HerSuiteMood._('Dusk', Color(0xFF0A0812), Color(0xFFC9ADFF));

  /// The moods offered as choices. `gold` reads the same as `standard` in
  /// the suite, so only one of them is offered.
  static const choices = <NeuraStageLighting>[
    NeuraStageLighting.standard,
    NeuraStageLighting.aurora,
    NeuraStageLighting.dusk,
  ];
}

String herSuiteCameraLabel(NeuraStageCamera camera) => switch (camera) {
      NeuraStageCamera.follow => 'Follow',
      NeuraStageCamera.wide => 'Wide',
      NeuraStageCamera.face => 'Face to face',
    };

/// The room behind the panels: a mood-lit backdrop with Neura framed by the
/// chosen camera. Resting settles her lower and dims the room.
class HerSuiteStage extends StatelessWidget {
  const HerSuiteStage({super.key, required this.stage, this.builder});

  final NeuraStagePresentation stage;
  final HerSuiteStageBuilder? builder;

  @override
  Widget build(BuildContext context) {
    final mood = HerSuiteMood.of(stage.lighting);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 600);
    final resting = stage.activity == NeuraCompanionActivity.resting;
    final (scale, alignment) = switch (stage.camera) {
      NeuraStageCamera.wide => (0.72, const Alignment(0, 0.55)),
      NeuraStageCamera.face => (1.55, const Alignment(0, 1.4)),
      NeuraStageCamera.follow => (1.0, const Alignment(0.25, 0.8)),
    };
    final lift = resting ? 0.25 : 0.0;
    final avatar = builder?.call(context, stage) ?? const _FlutterAvatarStage();

    return AnimatedContainer(
      key: const ValueKey('her-suite-stage'),
      duration: duration,
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.35, -0.3),
          radius: 1.2,
          colors: [
            Color.lerp(mood.background, mood.accent, resting ? 0.08 : 0.16)!,
            mood.background,
          ],
        ),
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: Curves.easeOutCubic,
        alignment: Alignment(alignment.x, alignment.y + lift),
        child: AnimatedScale(
          duration: duration,
          curve: Curves.easeOutCubic,
          scale: resting ? scale * 0.86 : scale,
          child: AnimatedOpacity(
            duration: duration,
            opacity: resting ? 0.82 : 1,
            child: FractionallySizedBox(
              heightFactor: 0.62,
              child: avatar,
            ),
          ),
        ),
      ),
    );
  }
}

class _FlutterAvatarStage extends StatelessWidget {
  const _FlutterAvatarStage();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NeuraPresenceSnapshot>(
      valueListenable: NeuraCompanionPresence.instance.state,
      builder: (context, presence, _) {
        return ValueListenableBuilder<ShellPrefs>(
          valueListenable: ShellPrefsController.instance.prefs,
          builder: (context, prefs, _) {
            return NeuraRoomPresenceAvatar(
              room: NeuraRoom.herSuite,
              phase: presence.phase,
              motion: prefs.companionMotion,
              scale: prefs.companionScale,
            );
          },
        );
      },
    );
  }
}

/// A frosted glass panel that sits over the stage.
class HerSuiteGlass extends StatelessWidget {
  const HerSuiteGlass({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          ),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
