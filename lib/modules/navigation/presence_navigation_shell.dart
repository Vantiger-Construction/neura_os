import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../neura_shell/models/neura_room.dart';
import '../../neura_shell/models/neura_room_presence_profile.dart';
import '../../neura_shell/widgets/neura_penthouse_scene.dart';
import '../../mood/services/neura_mood_weather.dart';
import '../../relationships/services/promise_garden.dart';
import '../../neura_shell/widgets/neura_room_presence_avatar.dart';
import '../../services/neura_companion_presence.dart';
import '../../src/shell/shell_prefs.dart';

enum PresenceLayoutMode { compact, wide }

class PresenceNavigationLayoutPolicy {
  const PresenceNavigationLayoutPolicy._();

  static const double wideBreakpoint = 960;

  static PresenceLayoutMode modeForWidth(double width) =>
      width >= wideBreakpoint
          ? PresenceLayoutMode.wide
          : PresenceLayoutMode.compact;
}

@immutable
class PresenceCommand {
  const PresenceCommand({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onSelected,
    this.keywords = const <String>[],
    this.pinned = false,
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onSelected;
  final List<String> keywords;
  final bool pinned;
}

@immutable
class PresenceShellStatus {
  const PresenceShellStatus({
    required this.safeMode,
    required this.cloudLabel,
    required this.voiceLabel,
    required this.presenceLabel,
    this.phase = NeuraPresencePhase.idle,
  });

  final bool safeMode;
  final String cloudLabel;
  final String voiceLabel;
  final String presenceLabel;
  final NeuraPresencePhase phase;
}

bool presenceCommandMatches(PresenceCommand command, String query) {
  final normalized = query.trim().toLowerCase();
  if (normalized.isEmpty) return true;
  final haystack = <String>[
    command.title,
    command.subtitle,
    ...command.keywords,
  ].join(' ').toLowerCase();
  return haystack.contains(normalized);
}

class PresenceNavigationShell extends StatefulWidget {
  const PresenceNavigationShell({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.destinationPages,
    required this.commands,
    required this.status,
    required this.now,
    required this.onOpenNeura,
    required this.onOpenDiagnostics,
    this.support,
    this.onListen,
    this.listenOnOpen,
    this.onListenOnOpenChanged,
    this.room = NeuraRoom.penthouse,
    this.preferences = ShellPrefs.defaults,
  }) : assert(destinationPages.length == 5);

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<Widget> destinationPages;
  final List<PresenceCommand> commands;
  final PresenceShellStatus status;
  final Widget now;
  final Widget? support;
  final VoidCallback onOpenNeura;
  final VoidCallback onOpenDiagnostics;

  /// Opens a voice turn with the microphone already listening. Hidden when
  /// null.
  final VoidCallback? onListen;

  /// The saved "listen when Neura opens" opt-in, shown as a switch in
  /// Neura's corner when both this and [onListenOnOpenChanged] are given.
  final ValueListenable<bool>? listenOnOpen;
  final ValueChanged<bool>? onListenOnOpenChanged;
  final NeuraRoom room;
  final ShellPrefs preferences;

  @override
  State<PresenceNavigationShell> createState() =>
      _PresenceNavigationShellState();
}

class _PresenceNavigationShellState extends State<PresenceNavigationShell> {
  static const _recentLimit = 5;

  final List<String> _recentCommandIds = <String>[];
  // Hidden destinations can own streams and services. Mount each one only
  // after a direct visit, then keep it in the stack so its local state lives.
  final Set<int> _mountedDestinationIndexes = <int>{0};
  late Map<String, PresenceCommand> _commandsById;
  late List<PresenceCommand> _pinnedCommands;
  bool _stageCollapsed = false;

  List<PresenceCommand> get _recentCommands => _recentCommandIds
      .map((id) => _commandsById[id])
      .whereType<PresenceCommand>()
      .toList(growable: false);

  @override
  void initState() {
    super.initState();
    _mountedDestinationIndexes.add(widget.currentIndex);
    _indexCommands();
    // The room's weather reflects the week's mood check-ins.
    unawaited(NeuraMoodWeatherService.instance.refresh());
    // The plant by the window shows the promises kept so far.
    unawaited(PromiseGardenService.instance.refresh());
  }

  @override
  void didUpdateWidget(PresenceNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    _mountedDestinationIndexes.add(widget.currentIndex);
    if (!identical(oldWidget.commands, widget.commands)) _indexCommands();
  }

  void _indexCommands() {
    _commandsById = <String, PresenceCommand>{
      for (final command in widget.commands) command.id: command,
    };
    _pinnedCommands = widget.commands
        .where((command) => command.pinned)
        .toList(growable: false);
  }

  void _runCommand(PresenceCommand command) {
    setState(() {
      _recentCommandIds
        ..remove(command.id)
        ..insert(0, command.id);
      if (_recentCommandIds.length > _recentLimit) {
        _recentCommandIds.removeRange(_recentLimit, _recentCommandIds.length);
      }
    });
    command.onSelected();
  }

  /// Null while voice is unavailable, which disables every mic control.
  VoidCallback? get _listen => widget.status.safeMode ? null : widget.onListen;

  Future<void> _openCommandPalette() async {
    final command = await showDialog<PresenceCommand>(
      context: context,
      builder: (context) => _PresenceCommandPalette(commands: widget.commands),
    );
    if (command != null && mounted) _runCommand(command);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final background = scheme.brightness == Brightness.dark
        ? const Color(0xFF0D0918)
        : const Color(0xFFF8F5FF);

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true):
            _openCommandPalette,
        const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
            _openCommandPalette,
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // The room Neura is in sits behind the whole menu, dimmed so the
            // workspace stays readable.
            ColoredBox(color: background),
            NeuraPenthouseScene(
              room: widget.room,
              dim: scheme.brightness == Brightness.dark ? 0.62 : 0.82,
              dimColor: background,
            ),
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final mode = PresenceNavigationLayoutPolicy.modeForWidth(
                    constraints.maxWidth,
                  );
                  return mode == PresenceLayoutMode.wide
                      ? _buildWide(context)
                      : _buildCompact(context);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWide(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _PresenceRail(
          selectedIndex: widget.currentIndex,
          onDestinationSelected: widget.onDestinationSelected,
        ),
        Expanded(child: _buildWorkspace(context)),
        // Neura's own corner: pinned to the far right edge, away from the
        // navigation rail and the workspace.
        AnimatedContainer(
          key: const ValueKey<String>('neura-corner'),
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          width: _stageCollapsed ? 84 : 276,
          padding: const EdgeInsets.fromLTRB(4, 12, 12, 12),
          child: _NeuraStage(
            collapsed: _stageCollapsed,
            status: widget.status,
            room: widget.room,
            preferences: widget.preferences,
            commands: widget.commands,
            onRunCommand: _runCommand,
            onOpenNeura: widget.onOpenNeura,
            onListen: _listen,
            showListen: widget.onListen != null,
            listenOnOpen: widget.listenOnOpen,
            onListenOnOpenChanged: widget.onListenOnOpenChanged,
            onToggleCollapsed: () =>
                setState(() => _stageCollapsed = !_stageCollapsed),
          ),
        ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: _CompactNeuraStage(
            status: widget.status,
            room: widget.room,
            preferences: widget.preferences,
            commands: widget.commands,
            onRunCommand: _runCommand,
            onOpenNeura: widget.onOpenNeura,
            onListen: _listen,
            showListen: widget.onListen != null,
          ),
        ),
        Expanded(child: _buildWorkspace(context, compact: true)),
        _PresenceBottomRail(
          selectedIndex: widget.currentIndex,
          onDestinationSelected: widget.onDestinationSelected,
        ),
      ],
    );
  }

  Widget _buildWorkspace(BuildContext context, {bool compact = false}) {
    final content = IndexedStack(
      index: widget.currentIndex,
      children: List<Widget>.generate(widget.destinationPages.length, (index) {
        if (!_mountedDestinationIndexes.contains(index)) {
          return const SizedBox.shrink();
        }
        if (index != 0) return widget.destinationPages[index];
        return _PresenceHomeSurface(
          now: widget.now,
          support: widget.support,
          pinnedCommands: _pinnedCommands,
          recentCommands: _recentCommands,
          onRunCommand: _runCommand,
          onOpenNeura: widget.onOpenNeura,
          onOpenDiagnostics: widget.onOpenDiagnostics,
        );
      }, growable: false),
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 8,
        10,
        compact ? 12 : 8,
        compact ? 4 : 12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _WorkspaceHeader(
            status: widget.status,
            onOpenPalette: _openCommandPalette,
            onListen: _listen,
            showListen: widget.onListen != null,
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: content,
            ),
          ),
        ],
      ),
    );
  }
}

const List<_PresenceDestination> _presenceDestinations = <_PresenceDestination>[
  _PresenceDestination('Home', Icons.home_outlined, Icons.home_rounded),
  _PresenceDestination('Spaces', Icons.layers_outlined, Icons.layers_rounded),
  _PresenceDestination('Care', Icons.favorite_outline, Icons.favorite_rounded),
  _PresenceDestination(
    'Memory',
    Icons.description_outlined,
    Icons.description_rounded,
  ),
  _PresenceDestination('Controls', Icons.tune_outlined, Icons.tune_rounded),
];

class _PresenceDestination {
  const _PresenceDestination(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

class _PresenceRail extends StatelessWidget {
  const _PresenceRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 112,
      margin: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: NavigationRail(
        backgroundColor: Colors.transparent,
        selectedIndex: selectedIndex,
        onDestinationSelected: onDestinationSelected,
        labelType: NavigationRailLabelType.all,
        leading: Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
            label: 'Neura Companion home navigation',
            child: CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.16),
              foregroundColor: scheme.primary,
              child: const Icon(Icons.auto_awesome_rounded),
            ),
          ),
        ),
        destinations: <NavigationRailDestination>[
          for (final destination in _presenceDestinations)
            NavigationRailDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: Text(destination.label),
            ),
        ],
      ),
    );
  }
}

class _PresenceBottomRail extends StatelessWidget {
  const _PresenceBottomRail({
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: selectedIndex,
      onDestinationSelected: onDestinationSelected,
      destinations: <NavigationDestination>[
        for (final destination in _presenceDestinations)
          NavigationDestination(
            icon: Icon(destination.icon),
            selectedIcon: Icon(destination.selectedIcon),
            label: destination.label,
          ),
      ],
    );
  }
}

class _NeuraStage extends StatelessWidget {
  const _NeuraStage({
    required this.collapsed,
    required this.status,
    required this.room,
    required this.preferences,
    required this.commands,
    required this.onRunCommand,
    required this.onOpenNeura,
    required this.onToggleCollapsed,
    this.onListen,
    this.showListen = false,
    this.listenOnOpen,
    this.onListenOnOpenChanged,
  });

  final bool collapsed;
  final PresenceShellStatus status;
  final NeuraRoom room;
  final ShellPrefs preferences;
  final List<PresenceCommand> commands;
  final ValueChanged<PresenceCommand> onRunCommand;
  final VoidCallback onOpenNeura;
  final VoidCallback onToggleCollapsed;
  final VoidCallback? onListen;
  final bool showListen;
  final ValueListenable<bool>? listenOnOpen;
  final ValueChanged<bool>? onListenOnOpenChanged;

  @override
  Widget build(BuildContext context) {
    const stageForeground = Color(0xFFF8F4FF);
    const stageMuted = Color(0xFFC8BEDA);
    final accent = Theme.of(context).colorScheme.primary;
    final profile = NeuraRoomPresenceProfile.forRoom(room);
    final activities = _roomActivities(profile, commands);

    return Semantics(
      container: true,
      label: 'Neura Stage. ${status.presenceLabel}',
      child: _PenthouseFrame(
        room: room,
        borderRadius: 28,
        accent: accent,
        glow: true,
        child: collapsed
            ? Column(
                children: <Widget>[
                  IconButton(
                    tooltip: 'Expand Neura Stage',
                    onPressed: onToggleCollapsed,
                    color: stageForeground,
                    icon: const Icon(Icons.open_in_full_rounded),
                  ),
                  const Spacer(),
                  SizedBox(
                    width: 60,
                    height: 72,
                    child: NeuraRoomPresenceAvatar(
                      room: room,
                      phase: status.safeMode
                          ? NeuraPresencePhase.safeMode
                          : status.phase,
                      motion: preferences.companionMotion,
                      scale: preferences.companionScale,
                      compact: true,
                    ),
                  ),
                  if (showListen) ...<Widget>[
                    const SizedBox(height: 8),
                    IconButton.filled(
                      tooltip: _ListenButton.tooltipFor(status),
                      onPressed: onListen,
                      icon: const Icon(Icons.mic_rounded),
                    ),
                  ],
                  const SizedBox(height: 12),
                  RotatedBox(
                    quarterTurns: 3,
                    child: Text(
                      'Neura is here',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: stageForeground,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const Spacer(),
                ],
              )
            : Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            'Neura is here',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  color: accent,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Collapse Neura Stage',
                          onPressed: onToggleCollapsed,
                          color: stageForeground,
                          icon: const Icon(Icons.close_fullscreen_rounded),
                        ),
                      ],
                    ),
                    Text(
                      status.presenceLabel,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: stageMuted),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${room.title} · ${profile.stanceLabel}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: accent),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      profile.cue,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: stageMuted),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: RadialGradient(
                            center: const Alignment(0, 0.35),
                            radius: 0.72,
                            colors: <Color>[
                              accent.withValues(alpha: 0.24),
                              const Color(0xFF171023).withValues(alpha: 0),
                            ],
                          ),
                        ),
                        child: NeuraRoomPresenceAvatar(
                          room: room,
                          phase: status.safeMode
                              ? NeuraPresencePhase.safeMode
                              : status.phase,
                          motion: preferences.companionMotion,
                          scale: preferences.companionScale,
                        ),
                      ),
                    ),
                    if (preferences.roomActivityHints &&
                        activities.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: <Widget>[
                          for (final command in activities.take(3))
                            ActionChip(
                              visualDensity: VisualDensity.compact,
                              avatar: Icon(command.icon, size: 15),
                              label: Text(command.title),
                              onPressed: () => onRunCommand(command),
                            ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (showListen) ...<Widget>[
                      _ListenButton(onListen: onListen, status: status),
                      const SizedBox(height: 6),
                      OutlinedButton.icon(
                        onPressed: onOpenNeura,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: stageForeground,
                          side: BorderSide(
                            color: stageForeground.withValues(alpha: 0.35),
                          ),
                        ),
                        icon: const Icon(Icons.keyboard_alt_outlined),
                        label: const Text('Type to Neura'),
                      ),
                    ] else
                      FilledButton.icon(
                        onPressed: onOpenNeura,
                        icon: const Icon(Icons.chat_bubble_outline_rounded),
                        label: const Text('Talk to Neura'),
                      ),
                    const SizedBox(height: 6),
                    _LiveVoiceLabel(status: status, color: stageMuted),
                    if (listenOnOpen != null && onListenOnOpenChanged != null)
                      ValueListenableBuilder<bool>(
                        valueListenable: listenOnOpen!,
                        builder: (context, enabled, _) => Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                'Listen as soon as Neura opens',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(color: stageForeground),
                              ),
                            ),
                            Switch(
                              key: const ValueKey<String>(
                                'listen-on-open-switch',
                              ),
                              value: enabled,
                              onChanged: status.safeMode
                                  ? null
                                  : onListenOnOpenChanged,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }
}

class _CompactNeuraStage extends StatelessWidget {
  const _CompactNeuraStage({
    required this.status,
    required this.room,
    required this.preferences,
    required this.commands,
    required this.onRunCommand,
    required this.onOpenNeura,
    this.onListen,
    this.showListen = false,
  });

  final PresenceShellStatus status;
  final NeuraRoom room;
  final ShellPrefs preferences;
  final List<PresenceCommand> commands;
  final ValueChanged<PresenceCommand> onRunCommand;
  final VoidCallback onOpenNeura;
  final VoidCallback? onListen;
  final bool showListen;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = NeuraRoomPresenceProfile.forRoom(room);
    final activities = _roomActivities(profile, commands);
    return Semantics(
      container: true,
      label: 'Neura presence panel. ${status.presenceLabel}',
      child: _PenthouseFrame(
        room: room,
        borderRadius: 22,
        accent: scheme.primary,
        showFurniture: false,
        child: Container(
          constraints: const BoxConstraints(minHeight: 88),
          padding: const EdgeInsets.all(10),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 60,
                height: 68,
                child: NeuraRoomPresenceAvatar(
                  room: room,
                  phase: status.safeMode
                      ? NeuraPresencePhase.safeMode
                      : status.phase,
                  motion: preferences.companionMotion,
                  scale: preferences.companionScale,
                  compact: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      'Neura is here',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status.presenceLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFFC8BEDA),
                          ),
                    ),
                    Text(
                      '${room.title} · ${profile.stanceLabel}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ),
              if (preferences.roomActivityHints && activities.isNotEmpty)
                IconButton(
                  tooltip: 'Try ${activities.first.title}',
                  onPressed: () => onRunCommand(activities.first),
                  icon: Icon(activities.first.icon),
                ),
              const SizedBox(width: 8),
              if (showListen) ...<Widget>[
                IconButton.filled(
                  tooltip: _ListenButton.tooltipFor(status),
                  onPressed: onListen,
                  icon: const Icon(Icons.mic_rounded),
                ),
                const SizedBox(width: 6),
              ],
              IconButton.filledTonal(
                tooltip: showListen ? 'Type to Neura' : 'Talk to Neura',
                onPressed: onOpenNeura,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The main way to talk to Neura from the menu: one tap opens a voice turn
/// that is already listening.
class _ListenButton extends StatelessWidget {
  const _ListenButton({required this.onListen, required this.status});

  final VoidCallback? onListen;
  final PresenceShellStatus status;

  static String tooltipFor(PresenceShellStatus status) => status.safeMode
      ? 'Voice is off in Safe Mode'
      : 'Talk to Neura. She listens right away';

  @override
  Widget build(BuildContext context) {
    final listening =
        !status.safeMode && status.phase == NeuraPresencePhase.listening;
    return Tooltip(
      message: tooltipFor(status),
      child: FilledButton.icon(
        key: const ValueKey<String>('neura-listen-button'),
        onPressed: onListen,
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          textStyle: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        icon: Icon(listening ? Icons.graphic_eq_rounded : Icons.mic_rounded),
        label: Text(
          status.safeMode
              ? 'Voice off'
              : listening
                  ? 'Listening…'
                  : 'Talk to Neura',
        ),
      ),
    );
  }
}

/// Voice state with a live dot while Neura is listening or speaking.
class _LiveVoiceLabel extends StatelessWidget {
  const _LiveVoiceLabel({required this.status, required this.color});

  final PresenceShellStatus status;
  final Color color;

  static const _liveColor = Color(0xFF5BE38C);

  @override
  Widget build(BuildContext context) {
    final live = !status.safeMode &&
        (status.phase == NeuraPresencePhase.listening ||
            status.phase == NeuraPresencePhase.speaking);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        if (live) ...<Widget>[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: _liveColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            status.voiceLabel,
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: live ? _liveColor : color),
          ),
        ),
      ],
    );
  }
}

/// Frames Neura's corner with the room she is in painted behind her.
class _PenthouseFrame extends StatelessWidget {
  const _PenthouseFrame({
    required this.room,
    required this.borderRadius,
    required this.accent,
    required this.child,
    this.glow = false,
    this.showFurniture = true,
  });

  final NeuraRoom room;
  final double borderRadius;
  final Color accent;
  final Widget child;
  final bool glow;
  final bool showFurniture;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: glow
            ? <BoxShadow>[
                BoxShadow(
                  color: accent.withValues(alpha: 0.08),
                  blurRadius: 30,
                  spreadRadius: 2,
                ),
              ]
            : null,
      ),
      position: DecorationPosition.background,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: accent.withValues(alpha: 0.42)),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Stack(
            fit: StackFit.passthrough,
            children: <Widget>[
              Positioned.fill(
                child: NeuraPenthouseScene(
                  key: const ValueKey<String>('neura-penthouse'),
                  room: room,
                  dim: 0.18,
                  dimColor: const Color(0xFF171023),
                  showFurniture: showFurniture,
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

List<PresenceCommand> _roomActivities(
  NeuraRoomPresenceProfile profile,
  List<PresenceCommand> commands,
) {
  final byId = <String, PresenceCommand>{
    for (final command in commands) command.id: command,
  };
  return profile.activityCommandIds
      .map((id) => byId[id])
      .whereType<PresenceCommand>()
      .toList(growable: false);
}

class _WorkspaceHeader extends StatelessWidget {
  const _WorkspaceHeader({
    required this.status,
    required this.onOpenPalette,
    this.onListen,
    this.showListen = false,
  });

  final PresenceShellStatus status;
  final VoidCallback onOpenPalette;
  final VoidCallback? onListen;
  final bool showListen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _StatusCapsule(status: status),
        const SizedBox(height: 8),
        Semantics(
          button: true,
          label: 'Open Neura command palette',
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onOpenPalette,
            child: Container(
              constraints: const BoxConstraints(minHeight: 54),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.search_rounded),
                  const SizedBox(width: 12),
                  const Expanded(child: Text('Ask Neura or type a command…')),
                  if (MediaQuery.of(context).size.width >= 700)
                    const _KeyboardHint(),
                  if (showListen) ...<Widget>[
                    const SizedBox(width: 6),
                    IconButton(
                      key: const ValueKey<String>('palette-mic'),
                      tooltip: _ListenButton.tooltipFor(status),
                      onPressed: onListen,
                      icon: const Icon(Icons.mic_none_rounded),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _KeyboardHint extends StatelessWidget {
  const _KeyboardHint();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text('Ctrl K'),
    );
  }
}

class _StatusCapsule extends StatelessWidget {
  const _StatusCapsule({required this.status});

  final PresenceShellStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: <Widget>[
          _StatusChip(
            icon:
                status.safeMode ? Icons.shield_rounded : Icons.shield_outlined,
            label: status.safeMode ? 'Safe Mode' : 'Standard Mode',
            color: status.safeMode ? scheme.error : scheme.primary,
          ),
          _StatusChip(
            icon: status.cloudLabel != 'Cloud gated'
                ? Icons.cloud_off_outlined
                : Icons.cloud_done_outlined,
            label: status.cloudLabel,
            color: scheme.secondary,
          ),
          _StatusChip(
            icon: status.voiceLabel == 'Voice off'
                ? Icons.mic_off_outlined
                : Icons.mic_none_rounded,
            label: status.voiceLabel,
            color: scheme.tertiary,
          ),
          _StatusChip(
            icon: Icons.approval_outlined,
            label: 'Approval every time',
            color: scheme.primary,
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _PresenceHomeSurface extends StatelessWidget {
  const _PresenceHomeSurface({
    required this.now,
    this.support,
    required this.pinnedCommands,
    required this.recentCommands,
    required this.onRunCommand,
    required this.onOpenNeura,
    required this.onOpenDiagnostics,
  });

  final Widget now;
  final Widget? support;
  final List<PresenceCommand> pinnedCommands;
  final List<PresenceCommand> recentCommands;
  final ValueChanged<PresenceCommand> onRunCommand;
  final VoidCallback onOpenNeura;
  final VoidCallback onOpenDiagnostics;

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _greeting(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'You’re not alone.',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Neura is here, quietly with you.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Open diagnostics',
                onPressed: onOpenDiagnostics,
                icon: const Icon(Icons.monitor_heart_outlined),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (support != null) ...[
            support!,
            const SizedBox(height: 16),
          ],
          _HomeSection(title: 'Now', subtitle: 'In this moment', child: now),
          const SizedBox(height: 14),
          _HomeSection(
            title: 'Next',
            subtitle: 'Choose one gentle step',
            child: pinnedCommands.isEmpty
                ? _EmptyHomeState(
                    icon: Icons.explore_outlined,
                    message: 'Open the command palette to choose what is next.',
                    onTap: onOpenNeura,
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: <Widget>[
                      for (final command in pinnedCommands.take(4))
                        _HomeCommandCard(
                          command: command,
                          onTap: () => onRunCommand(command),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 14),
          _HomeSection(
            title: 'Recent',
            subtitle: 'This session only',
            child: recentCommands.isEmpty
                ? const _EmptyHomeState(
                    icon: Icons.history_rounded,
                    message:
                        'Nothing opened yet. Your private history is not uploaded.',
                  )
                : Column(
                    children: <Widget>[
                      for (final command in recentCommands)
                        ListTile(
                          minTileHeight: 52,
                          leading: Icon(command.icon),
                          title: Text(command.title),
                          subtitle: Text(command.subtitle),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => onRunCommand(command),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _HomeCommandCard extends StatelessWidget {
  const _HomeCommandCard({required this.command, required this.onTap});

  final PresenceCommand command;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 210,
      child: Card(
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerHighest,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 112),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(command.icon, color: scheme.primary),
                  const SizedBox(height: 10),
                  Text(
                    command.title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 3),
                  Text(command.subtitle),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHomeState extends StatelessWidget {
  const _EmptyHomeState({
    required this.icon,
    required this.message,
    this.onTap,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Row(
          children: <Widget>[
            Icon(icon),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}

class _PresenceCommandPalette extends StatefulWidget {
  const _PresenceCommandPalette({required this.commands});

  final List<PresenceCommand> commands;

  @override
  State<_PresenceCommandPalette> createState() =>
      _PresenceCommandPaletteState();
}

class _PresenceCommandPaletteState extends State<_PresenceCommandPalette> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = widget.commands
        .where((command) => presenceCommandMatches(command, _query))
        .toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: <Widget>[
              TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  labelText: 'Find a room or action',
                  hintText: 'Journal, dreams, care, memory…',
                ),
                onChanged: (value) => setState(() => _query = value),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: matches.isEmpty
                    ? const Center(child: Text('No matching Neura spaces.'))
                    : ListView.builder(
                        itemCount: matches.length,
                        itemBuilder: (context, index) {
                          final command = matches[index];
                          return ListTile(
                            minTileHeight: 58,
                            leading: Icon(command.icon),
                            title: Text(command.title),
                            subtitle: Text(command.subtitle),
                            trailing: command.pinned
                                ? const Icon(
                                    Icons.push_pin_outlined,
                                    semanticLabel: 'Pinned',
                                  )
                                : null,
                            onTap: () => Navigator.of(context).pop(command),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
