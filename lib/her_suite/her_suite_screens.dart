import 'dart:async';
import 'dart:math' as math;

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

  // A visit never changes the saved room.
  @override
  Future<void> setRoom(NeuraRoom room) => _shell.setRoom(room, persist: false);
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

  static Widget _suggestions(BuildContext _) {
    return const NeuraIntelligenceCenterScreen();
  }
}

void _open(BuildContext context, String name, WidgetBuilder builder) {
  final route = MaterialPageRoute<void>(
    builder: builder,
    settings: RouteSettings(name: name),
  );
  Navigator.of(context).push(route);
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

  /// The stage the app's Her Suite visits use when none is passed: null
  /// shows the Flutter avatar. The Unity integration sets this once at
  /// startup to host the Unity window.
  static HerSuiteStageBuilder? appStageBuilder;

  /// Whether a Her Suite visit is on screen.
  static bool get visiting => _visits > 0;
  static int _visits = 0;

  /// Opens a visit, unless one is already open: a second suite on top
  /// would fight the first over the room and the stage.
  static Future<void> open(BuildContext context) {
    if (visiting) return Future<void>.value();
    final route = MaterialPageRoute<void>(
      builder: (_) => HerSuiteScreen(stageBuilder: appStageBuilder),
      settings: const RouteSettings(name: '/her-suite'),
    );
    return Navigator.of(context).push(route);
  }

  @override
  State<HerSuiteScreen> createState() => _HerSuiteScreenState();
}

class _HerSuiteScreenState extends State<HerSuiteScreen> {
  late final HerSuiteStageController _controller =
      widget.controller ?? HerSuiteStageController();
  AppHerShelfSource? _ownedShelf;
  HerSuiteHost? _host;
  NeuraRoom? _previousRoom;
  Future<void> _entry = Future<void>.value();

  @override
  void initState() {
    super.initState();
    HerSuiteScreen._visits++;
  }

  HerShelfSource get _shelf {
    return widget.shelf ?? (_ownedShelf ??= AppHerShelfSource());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_host != null) return;
    final host = widget.host ?? _ShellHost(NeuraShell.of(context));
    _host = host;
    final current = host.room;
    if (current.id == NeuraRoom.herSuite.id) return;
    _previousRoom = current;
    // Room changes notify the shell's listeners, which must not rebuild
    // while this route is still building; run them after this frame's
    // synchronous work.
    final entry = Completer<void>();
    _entry = entry.future;
    scheduleMicrotask(() {
      if (mounted) {
        entry.complete(_move(host, NeuraRoom.herSuite));
      } else {
        entry.complete();
      }
    });
  }

  /// A failed move only loses optional room extras (the ambient loop); the
  /// shell has already switched rooms in memory. Report it and carry on.
  static Future<void> _move(HerSuiteHost host, NeuraRoom room) {
    return host.setRoom(room).catchError((Object error, StackTrace stack) {
      FlutterError.reportError(FlutterErrorDetails(
        exception: error,
        stack: stack,
        library: 'her suite',
        context: ErrorDescription('while moving to ${room.id}'),
      ));
    });
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
    final entry = _entry;
    HerSuiteScreen._visits--;
    scheduleMicrotask(() {
      if (previous != null && host != null) {
        // Restore only after the entry move finishes, so it can't land last,
        // and only if nothing else moved Neura while the suite was open.
        unawaited(entry.then((_) async {
          if (host.room.id != NeuraRoom.herSuite.id) return;
          await _move(host, previous);
        }));
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

  void _openSitTogether() {
    _open(context, '/her-suite/sit-together', (_) {
      return HerSitTogetherScreen(
        controller: _controller,
        destinations: widget.destinations,
        stageBuilder: widget.stageBuilder,
      );
    });
  }

  void _openShelf() {
    _open(context, '/her-suite/shelf', (_) {
      return HerShelfScreen(
        controller: _controller,
        source: _shelf,
        destinations: widget.destinations,
        stageBuilder: widget.stageBuilder,
      );
    });
  }

  void _openResting() {
    _open(context, '/her-suite/resting', (_) {
      return HerRestingScreen(
        controller: _controller,
        stageBuilder: widget.stageBuilder,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final profile = NeuraRoomPresenceProfile.forRoom(NeuraRoom.herSuite);
    return _SuiteScaffold(
      controller: _controller,
      stageBuilder: widget.stageBuilder,
      title: 'Her Suite',
      subtitle: profile.cue,
      panel: _buildPanel,
    );
  }

  Widget _buildPanel(BuildContext context) {
    final safeMode = _controller.safeMode;
    final restHint =
        safeMode ? 'Not in Safe Mode' : 'She settles by the window';
    return Column(
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
              onTap: _openSitTogether,
            ),
            _SuiteAction(
              key: const ValueKey('her-suite-shelf'),
              icon: Icons.auto_stories_outlined,
              title: 'Her shelf',
              subtitle: 'What you have taught her',
              onTap: _openShelf,
            ),
            _SuiteAction(
              key: const ValueKey('her-suite-rest'),
              icon: Icons.nights_stay_outlined,
              title: 'Let her rest',
              subtitle: restHint,
              onTap: safeMode ? null : _openResting,
            ),
          ],
        ),
      ],
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
    // The suite underneath rebuilds on stage changes, so change it after
    // this frame rather than while the route is building.
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

  void _talk() {
    _open(context, '/her-suite/sit-together/chat', widget.destinations.chat);
  }

  @override
  Widget build(BuildContext context) {
    return _SuiteScaffold(
      controller: widget.controller,
      stageBuilder: widget.stageBuilder,
      title: 'Sit together',
      subtitle: 'On her sofa, face to face.',
      panel: _buildPanel,
    );
  }

  Widget _buildPanel(BuildContext context) {
    if (_quiet) {
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => setState(() => _quiet = false),
          child: const Text('Show options'),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Talk with her, or just keep each other company.'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('her-suite-talk'),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Talk with her'),
                onPressed: _talk,
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

  @override
  Widget build(BuildContext context) {
    return _SuiteScaffold(
      controller: widget.controller,
      stageBuilder: widget.stageBuilder,
      title: 'Her shelf',
      subtitle: 'What you have taught her. Only you can change it.',
      panel: (context) {
        return ListenableBuilder(
          listenable: widget.source,
          builder: (context, _) => _buildShelf(widget.source.read()),
        );
      },
    );
  }

  Widget _buildShelf(HerShelfSummary shelf) {
    if (shelf.safeMode) {
      return const ListTile(
        key: ValueKey('her-shelf-closed'),
        leading: Icon(Icons.shield_outlined),
        title: Text('Her shelf is closed in Safe Mode'),
        subtitle: Text('Restart normally to see or change it.'),
      );
    }
    final destinations = widget.destinations;
    void teach() => _open(context, '/teach', destinations.teach);
    void suggestions() {
      _open(context, '/intelligence', destinations.suggestions);
    }

    final canTeach = shelf.teachingAvailable;
    final answers = _taught(
      shelf,
      shelf.answerDetail?.label,
      shelf.answerIsTemporary,
    );
    final plans = _taught(
      shelf,
      shelf.planSize?.label,
      shelf.planIsTemporary,
    );
    final quiet = shelf.quietHoursEnabled
        ? '${_hour(shelf.quietHoursStart)} to ${_hour(shelf.quietHoursEnd)}'
        : 'Off';
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ShelfItem(
          key: const ValueKey('her-shelf-answers'),
          icon: Icons.notes_outlined,
          title: 'How you like answers',
          value: answers,
          onTap: canTeach ? teach : null,
        ),
        _ShelfItem(
          key: const ValueKey('her-shelf-plans'),
          icon: Icons.checklist_outlined,
          title: 'Plan size',
          value: plans,
          onTap: canTeach ? teach : null,
        ),
        _ShelfItem(
          key: const ValueKey('her-shelf-suggestions'),
          icon: Icons.lightbulb_outline,
          title: 'Suggestions',
          value: shelf.suggestions.label,
          onTap: suggestions,
        ),
        _ShelfItem(
          key: const ValueKey('her-shelf-quiet'),
          icon: Icons.bedtime_outlined,
          title: 'Quiet hours',
          value: quiet,
          onTap: suggestions,
        ),
        _ShelfItem(
          key: const ValueKey('her-shelf-memories'),
          icon: Icons.lock_outline,
          title: 'Memories',
          value: 'Encrypted on this device. Review or forget them.',
          onTap: () => _open(context, '/memory', destinations.memory),
        ),
      ],
    );
  }

  static String _taught(HerShelfSummary shelf, String? label, bool today) {
    if (!shelf.teachingAvailable) return 'Unavailable right now';
    if (shelf.teachingUnreadable) return 'Could not be read';
    if (label == null) return 'Not taught yet';
    return today ? '$label (today only)' : label;
  }

  static String _hour(int hour) => '${hour.toString().padLeft(2, '0')}:00';
}

/// Resting: she settles by the window and the room dims. Leaving wakes her.
/// Safe Mode wakes her and closes this screen.
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
      panel: (context) {
        return Row(
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
        );
      },
    );
  }
}

/// The stage with a title panel on top and [panel] at the bottom. Both are
/// rebuilt whenever the stage changes.
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
  final WidgetBuilder panel;
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
    final accent = HerSuiteMood.of(controller.stage.lighting).accent;
    final scheme = theme.colorScheme.copyWith(primary: accent);
    final text = theme.textTheme;
    final header = HerSuiteGlass(
      padding: const EdgeInsets.fromLTRB(6, 6, 18, 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const BackButton(),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleMedium),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
    return Theme(
      data: theme.copyWith(colorScheme: scheme),
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
              child: LayoutBuilder(builder: _layoutPanels(header)),
            ),
          ],
        ),
      ),
    );
  }

  /// Header at the top and the panel at the bottom; on short screens or
  /// with large text the two scroll instead of overflowing.
  LayoutWidgetBuilder _layoutPanels(Widget header) {
    return (context, constraints) {
      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 32),
          ),
          // The column is at least the screen's height, so spaceBetween
          // pins the header to the top and the panel to the bottom; taller
          // content just scrolls. (IntrinsicHeight misjudges wrapped tiles.)
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              header,
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: HerSuiteGlass(
                  child: Builder(builder: panel),
                ),
              ),
            ],
          ),
        ),
      );
    };
  }
}

class _StageChoices extends StatelessWidget {
  const _StageChoices({required this.controller});

  final HerSuiteStageController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    final mood = HerSuiteMood.of(stage.lighting);
    final label = Theme.of(context).textTheme.labelMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Light', style: label),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          children: [
            for (final lighting in HerSuiteMood.choices)
              ChoiceChip(
                key: ValueKey('her-suite-light-${lighting.name}'),
                label: Text(HerSuiteMood.of(lighting).label),
                selected: mood == HerSuiteMood.of(lighting),
                onSelected: (_) => controller.setLighting(lighting),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text('View', style: label),
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
    final alpha = onTap == null ? 0.03 : 0.08;
    return SizedBox(
      width: 160,
      child: Card(
        color: Colors.white.withValues(alpha: alpha),
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
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right),
      onTap: onTap,
    );
  }
}
