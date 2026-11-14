import 'dart:async';

import 'package:flutter/material.dart';

import '../avatar/neura_avatar_runtime_bridge.dart';
import '../intelligence/intelligence_center_screen.dart';
import '../intelligence/intelligence_preferences.dart';
import '../modules/chat/neura_chat_screen.dart';
import '../modules/memory/memory_screen.dart';
import '../neura_shell/models/neura_room.dart';
import '../neura_shell/models/neura_room_presence_profile.dart';
import '../neura_shell/neura_shell.dart';
import '../neura_shell/neura_shell_state.dart';
import '../teaching/neura_teaching_preferences.dart';
import '../teaching/teach_neura_screen.dart';
import 'her_shelf_source.dart';
import 'her_suite_stage.dart';
import 'her_suite_stage_controller.dart';

/// Switches the shell's room. The app uses the shell; tests use a fake.
abstract class HerSuiteHost {
  NeuraRoom get room;
  Future<void> setRoom(NeuraRoom room);
}

class _ShellHost implements HerSuiteHost {
  // Holds the shell itself, not a context: the room is restored after this
  // screen has left the tree.
  _ShellHost(this._shell);
  final NeuraShellState _shell;
  @override
  NeuraRoom get room => _shell.room;
  @override
  Future<void> setRoom(NeuraRoom room) => _shell.setRoom(room);
}

/// The existing screens Her Suite opens. Each keeps its own consent and
/// privacy rules; Her Suite only links to them.
class HerSuiteDestinations {
  const HerSuiteDestinations({
    this.chat = _chat,
    this.teach = _teach,
    this.memory = _memory,
    this.suggestions = _suggestions,
  });

  final WidgetBuilder chat;
  final WidgetBuilder teach;
  final WidgetBuilder memory;
  final WidgetBuilder suggestions;

  static Widget _chat(BuildContext _) => const NeuraChatScreen();
  static Widget _teach(BuildContext _) => const NeuraTeachScreen();
  static Widget _memory(BuildContext _) => const MemoryScreen();
  static Widget _suggestions(BuildContext _) =>
      const NeuraIntelligenceCenterScreen();
}

/// Neura's own room. You visit it as a guest: opening it moves the shell to
/// Her Suite, and leaving puts you back in the room you came from.
///
/// The stage behind the panels is a slot ([stageBuilder]); it shows the
/// Flutter avatar now and can host the Unity window later. Only the
/// display-only stage values (lighting, camera, resting) ever reach the
/// stage. Chat, memory and settings stay in the Flutter panels and the
/// screens they open.
class HerSuiteScreen extends StatefulWidget {
  const HerSuiteScreen({
    super.key,
    this.host,
    this.controller,
    this.shelf,
    this.destinations = const HerSuiteDestinations(),
    this.stageBuilder,
  });

  final HerSuiteHost? host;
  final HerSuiteStageController? controller;
  final HerShelfSource? shelf;
  final HerSuiteDestinations destinations;
  final HerSuiteStageBuilder? stageBuilder;

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => const HerSuiteScreen(),
        settings: const RouteSettings(name: '/her-suite'),
      ));

  @override
  State<HerSuiteScreen> createState() => _HerSuiteScreenState();
}

class _HerSuiteScreenState extends State<HerSuiteScreen> {
  late final HerSuiteStageController _controller =
      widget.controller ?? HerSuiteStageController();
  AppHerShelfSource? _ownedShelf;
  HerSuiteHost? _host;
  NeuraRoom? _previousRoom;

  HerShelfSource get _shelf =>
      widget.shelf ?? (_ownedShelf ??= AppHerShelfSource());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_host != null) return;
    final host = _host = widget.host ?? _ShellHost(NeuraShell.of(context));
    final current = host.room;
    if (current.id != NeuraRoom.herSuite.id) {
      _previousRoom = current;
      // Room changes notify the shell's listeners, which must not rebuild
      // while this route is still building; run them after this frame's
      // synchronous work.
      scheduleMicrotask(() {
        if (!mounted) return;
        unawaited(host.setRoom(NeuraRoom.herSuite).catchError((_) {}));
      });
    }
  }

  @override
  void dispose() {
    final previous = _previousRoom;
    final host = _host;
    final controller = _controller;
    final owned = widget.controller == null;
    final shelf = _ownedShelf;
    // Leaving notifies the shell and the presence bridge. Do it outside
    // the locked dispose phase.
    scheduleMicrotask(() {
      if (previous != null && host != null) {
        unawaited(host.setRoom(previous).catchError((_) {}));
      }
      if (owned) {
        controller.dispose();
      } else {
        controller.close();
      }
      shelf?.dispose();
    });
    super.dispose();
  }

  void _push(Widget screen, String name) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => screen,
      settings: RouteSettings(name: name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cue = NeuraRoomPresenceProfile.forRoom(NeuraRoom.herSuite).cue;
    return _SuiteScaffold(
      controller: _controller,
      stageBuilder: widget.stageBuilder,
      title: 'Her Suite',
      subtitle: cue,
      panel: ListenableBuilder(
        listenable: _controller,
        builder: (context, _) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StageChoices(controller: _controller),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                _SuiteAction(
                  key: const ValueKey('her-suite-sit'),
                  icon: Icons.weekend_outlined,
                  title: 'Sit together',
                  subtitle: 'Face to face on her sofa',
                  onTap: () => _push(
                      HerSitTogetherScreen(
                        controller: _controller,
                        destinations: widget.destinations,
                        stageBuilder: widget.stageBuilder,
                      ),
                      '/her-suite/sit-together'),
                ),
                _SuiteAction(
                  key: const ValueKey('her-suite-shelf'),
                  icon: Icons.auto_stories_outlined,
                  title: 'Her shelf',
                  subtitle: 'What you have taught her',
                  onTap: () => _push(
                      HerShelfScreen(
                        controller: _controller,
                        source: _shelf,
                        destinations: widget.destinations,
                        stageBuilder: widget.stageBuilder,
                      ),
                      '/her-suite/shelf'),
                ),
                _SuiteAction(
                  key: const ValueKey('her-suite-rest'),
                  icon: Icons.nights_stay_outlined,
                  title: 'Let her rest',
                  subtitle: _controller.safeMode
                      ? 'Not in Safe Mode'
                      : 'She settles by the window',
                  onTap: _controller.safeMode
                      ? null
                      : () => _push(
                          HerRestingScreen(
                            controller: _controller,
                            stageBuilder: widget.stageBuilder,
                          ),
                          '/her-suite/resting'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Sitting together: the camera comes face to face, and the panel offers a
/// conversation. Leaving puts the camera back where it was.
class HerSitTogetherScreen extends StatefulWidget {
  const HerSitTogetherScreen({
    super.key,
    required this.controller,
    this.destinations = const HerSuiteDestinations(),
    this.stageBuilder,
  });

  final HerSuiteStageController controller;
  final HerSuiteDestinations destinations;
  final HerSuiteStageBuilder? stageBuilder;

  @override
  State<HerSitTogetherScreen> createState() => _HerSitTogetherScreenState();
}

class _HerSitTogetherScreenState extends State<HerSitTogetherScreen> {
  late final NeuraStageCamera _previous;
  bool _quiet = false;

  @override
  void initState() {
    super.initState();
    _previous = widget.controller.stage.camera;
    // The parent suite rebuilds on stage changes, so change it after this
    // frame rather than while the route is building.
    scheduleMicrotask(() {
      if (mounted) widget.controller.setCamera(NeuraStageCamera.face);
    });
  }

  @override
  void dispose() {
    final controller = widget.controller;
    final previous = _previous;
    scheduleMicrotask(() => controller.setCamera(previous));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return _SuiteScaffold(
      controller: widget.controller,
      stageBuilder: widget.stageBuilder,
      title: 'Sit together',
      subtitle: 'On her sofa, face to face.',
      panel: _quiet
          ? Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _quiet = false),
                child: const Text('Show options'),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Talk with her, or just keep each other company.',
                    style: text.bodyMedium),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        key: const ValueKey('her-suite-talk'),
                        icon: const Icon(Icons.chat_bubble_outline),
                        label: const Text('Talk with her'),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: widget.destinations.chat,
                            settings: const RouteSettings(
                                name: '/her-suite/sit-together/chat'),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      key: const ValueKey('her-suite-quiet'),
                      onPressed: () => setState(() => _quiet = true),
                      child: const Text('Just sit'),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// Her shelf: the settings you have taught her, as labels, each linking to
/// the screen that owns it. No memories or conversations are shown here.
class HerShelfScreen extends StatefulWidget {
  const HerShelfScreen({
    super.key,
    required this.controller,
    required this.source,
    this.destinations = const HerSuiteDestinations(),
    this.stageBuilder,
  });

  final HerSuiteStageController controller;
  final HerShelfSource source;
  final HerSuiteDestinations destinations;
  final HerSuiteStageBuilder? stageBuilder;

  @override
  State<HerShelfScreen> createState() => _HerShelfScreenState();
}

class _HerShelfScreenState extends State<HerShelfScreen> {
  @override
  void initState() {
    super.initState();
    widget.source.ensureLoaded();
  }

  void _open(WidgetBuilder builder, String name) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: builder,
      settings: RouteSettings(name: name),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return _SuiteScaffold(
      controller: widget.controller,
      stageBuilder: widget.stageBuilder,
      title: 'Her shelf',
      subtitle: 'What you have taught her. Only you can change it.',
      panel: ListenableBuilder(
        listenable: widget.source,
        builder: (context, _) {
          final shelf = widget.source.read();
          if (shelf.safeMode) {
            return const ListTile(
              key: ValueKey('her-shelf-closed'),
              leading: Icon(Icons.shield_outlined),
              title: Text('Her shelf is closed in Safe Mode'),
              subtitle: Text('Restart normally to see or change it.'),
            );
          }
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _ShelfItem(
                key: const ValueKey('her-shelf-answers'),
                icon: Icons.notes_outlined,
                title: 'How you like answers',
                value: _taught(shelf, shelf.answerDetail?.label,
                    shelf.answerIsTemporary),
                onTap: shelf.teachingAvailable
                    ? () => _open(widget.destinations.teach, '/teach')
                    : null,
              ),
              _ShelfItem(
                key: const ValueKey('her-shelf-plans'),
                icon: Icons.checklist_outlined,
                title: 'Plan size',
                value: _taught(
                    shelf, shelf.planSize?.label, shelf.planIsTemporary),
                onTap: shelf.teachingAvailable
                    ? () => _open(widget.destinations.teach, '/teach')
                    : null,
              ),
              _ShelfItem(
                key: const ValueKey('her-shelf-suggestions'),
                icon: Icons.lightbulb_outline,
                title: 'Suggestions',
                value: shelf.suggestions.label,
                onTap: () =>
                    _open(widget.destinations.suggestions, '/intelligence'),
              ),
              _ShelfItem(
                key: const ValueKey('her-shelf-quiet'),
                icon: Icons.bedtime_outlined,
                title: 'Quiet hours',
                value: shelf.quietHoursEnabled
                    ? '${_hour(shelf.quietHoursStart)} to '
                        '${_hour(shelf.quietHoursEnd)}'
                    : 'Off',
                onTap: () =>
                    _open(widget.destinations.suggestions, '/intelligence'),
              ),
              _ShelfItem(
                key: const ValueKey('her-shelf-memories'),
                icon: Icons.lock_outline,
                title: 'Memories',
                value: 'Encrypted on this device. Review or forget them.',
                onTap: () => _open(widget.destinations.memory, '/memory'),
              ),
            ],
          );
        },
      ),
    );
  }

  static String _taught(HerShelfSummary shelf, String? label, bool today) {
    if (!shelf.teachingAvailable) return 'Unavailable right now';
    if (label == null) return 'Not taught yet';
    return today ? '$label (today only)' : label;
  }

  static String _hour(int hour) => '${hour.toString().padLeft(2, '0')}:00';
}

/// Resting: she settles by the window and the room dims. Leaving wakes her.
/// Safe Mode wakes her at once and closes this screen.
class HerRestingScreen extends StatefulWidget {
  const HerRestingScreen({
    super.key,
    required this.controller,
    this.stageBuilder,
  });

  final HerSuiteStageController controller;
  final HerSuiteStageBuilder? stageBuilder;

  @override
  State<HerRestingScreen> createState() => _HerRestingScreenState();
}

class _HerRestingScreenState extends State<HerRestingScreen> {
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    scheduleMicrotask(() {
      if (mounted) widget.controller.rest();
    });
  }

  void _onChange() {
    if (!mounted || _leaving || !widget.controller.safeMode) return;
    _leaving = true;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    final controller = widget.controller;
    controller.removeListener(_onChange);
    scheduleMicrotask(controller.wake);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _SuiteScaffold(
      controller: widget.controller,
      stageBuilder: widget.stageBuilder,
      title: 'Resting',
      subtitle: 'Neura is resting by the window.',
      panel: Row(
        children: [
          const Expanded(
            child: Text('She will still answer if you call her.'),
          ),
          FilledButton.tonal(
            key: const ValueKey('her-suite-wake'),
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('Wake her'),
          ),
        ],
      ),
    );
  }
}

class _SuiteScaffold extends StatelessWidget {
  const _SuiteScaffold({
    required this.controller,
    required this.title,
    required this.subtitle,
    required this.panel,
    this.stageBuilder,
  });

  final HerSuiteStageController controller;
  final String title;
  final String subtitle;
  final Widget panel;
  final HerSuiteStageBuilder? stageBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => _build(context),
    );
  }

  Widget _build(BuildContext context) {
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: HerSuiteMood.of(controller.stage.lighting).accent,
        ),
      ),
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            Positioned.fill(
              child: HerSuiteStage(
                stage: controller.stage,
                builder: stageBuilder,
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    HerSuiteGlass(
                      padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const BackButton(),
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(title, style: theme.textTheme.titleMedium),
                                Text(subtitle,
                                    style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560),
                      child: HerSuiteGlass(child: panel),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageChoices extends StatelessWidget {
  const _StageChoices({required this.controller});

  final HerSuiteStageController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Light', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final lighting in HerSuiteMood.choices)
              ChoiceChip(
                key: ValueKey('her-suite-light-${lighting.name}'),
                label: Text(HerSuiteMood.of(lighting).label),
                selected: HerSuiteMood.of(stage.lighting) ==
                    HerSuiteMood.of(lighting),
                onSelected: (_) => controller.setLighting(lighting),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('View', style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final camera in NeuraStageCamera.values)
              ChoiceChip(
                key: ValueKey('her-suite-camera-${camera.name}'),
                label: Text(herSuiteCameraLabel(camera)),
                selected: stage.camera == camera,
                onSelected: (_) => controller.setCamera(camera),
              ),
          ],
        ),
      ],
    );
  }
}

class _SuiteAction extends StatelessWidget {
  const _SuiteAction({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 160,
      child: Card(
        color: Colors.white.withValues(alpha: onTap == null ? 0.03 : 0.08),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(height: 8),
                Text(title, style: theme.textTheme.titleSmall),
                Text(subtitle, style: theme.textTheme.bodySmall),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ShelfItem extends StatelessWidget {
  const _ShelfItem({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(value),
        trailing: onTap == null ? null : const Icon(Icons.chevron_right),
        onTap: onTap,
      );
}
