import 'dart:async';

import 'package:flutter/material.dart';

import '../modules/support/support_page_shortcuts.dart';

enum _LoungeAction { none, quietWriting, smallStep, settle }

class _LoungeSpot {
  const _LoungeSpot(
    this.id,
    this.label,
    this.position,
    this.icon,
    this.title,
    this.description,
    this.examples, {
    this.action = _LoungeAction.none,
  });

  final String id;
  final String label;
  final Offset position;
  final IconData icon;
  final String title;
  final String description;
  final List<String> examples;
  final _LoungeAction action;
}

// Source hotspot IDs/labels come from the archived Lounge room profile.
// Positions are authored for the 16:9 artwork, not projected Unity coordinates.
const _spots = <_LoungeSpot>[
  _LoungeSpot(
    'sofa_seat',
    'Talk',
    Offset(0.35, 0.72),
    Icons.chat_bubble_outline,
    'A place to talk',
    'Sample conversation prompts for a quiet seat by the window. '
        'This room preview does not listen or generate replies.',
    [
      'What would make this afternoon a little easier?',
      'What went well today?',
    ],
  ),
  _LoungeSpot(
    'coffee_table',
    'Brainstorm',
    Offset(0.51, 0.84),
    Icons.lightbulb_outline,
    'Make room for an idea',
    'These fictional ideas show how a conversation could become a small step.',
    ['Sketch a reading corner.', 'Choose a book for the weekend.'],
    action: _LoungeAction.smallStep,
  ),
  _LoungeSpot(
    'reflection_window',
    'Reflect',
    Offset(0.73, 0.33),
    Icons.wb_twilight,
    'A moment to reflect',
    'Try the existing quiet-writing activity with a made-up example. '
        'Writing clears when you leave that activity.',
    ['What would a calmer evening look like?'],
    action: _LoungeAction.quietWriting,
  ),
  _LoungeSpot(
    'memory_cards',
    'Memory',
    Offset(0.18, 0.40),
    Icons.style_outlined,
    'Sample reflections',
    'Fictional cards illustrate this part of the room. '
        'No saved memories or journals are opened.',
    [
      'Sample: A quiet afternoon with a book.',
      'Sample: An idea for a cozy corner.',
    ],
  ),
  _LoungeSpot(
    'office_handoff',
    'Office',
    Offset(0.08, 0.86),
    Icons.checklist_outlined,
    'Give an idea a next step',
    'An Office connection is part of the room concept. '
        'For now, try the existing small-step activity with a fictional task.',
    ['Sample task: Clear one corner of a desk.'],
    action: _LoungeAction.smallStep,
  ),
  _LoungeSpot(
    'spa_handoff',
    'Spa',
    Offset(0.92, 0.86),
    Icons.spa_outlined,
    'Take a quiet pause',
    'A Spa connection is part of the room concept. '
        'Try the existing guided-support choices in this sample session.',
    ['Choose a quiet pause, grounding, or an optional breathing guide.'],
    action: _LoungeAction.settle,
  ),
];

/// A room concept inside the attested, in-memory NEURA_DEMO host only.
/// Destinations are injected so this screen has no production service access.
class NeuraLoungePreviewScreen extends StatefulWidget {
  const NeuraLoungePreviewScreen({
    super.key,
    required this.quietWritingBuilder,
    required this.smallStepBuilder,
    required this.settleBuilder,
    this.artworkAsset = 'assets/preview/lounge/lounge.png',
  });

  final WidgetBuilder quietWritingBuilder;
  final WidgetBuilder smallStepBuilder;
  final WidgetBuilder settleBuilder;
  final String artworkAsset;

  @override
  State<NeuraLoungePreviewScreen> createState() =>
      _NeuraLoungePreviewScreenState();
}

class _NeuraLoungePreviewScreenState extends State<NeuraLoungePreviewScreen>
    with WidgetsBindingObserver {
  _LoungeSpot? _selected;
  final _selectionAnchor = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _selected != null) {
      setState(() => _selected = null);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _select(_LoungeSpot spot) {
    setState(() => _selected = spot);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _selected != spot) return;
      final target = _selectionAnchor.currentContext;
      if (target != null && (ModalRoute.of(context)?.isCurrent ?? true)) {
        // An explicit choice reveals its result without animated scrolling.
        unawaited(Scrollable.ensureVisible(target, duration: Duration.zero));
      }
    });
  }

  void _open(WidgetBuilder builder) {
    unawaited(
      Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (context) => SupportPageShortcuts(child: builder(context)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SupportPageShortcuts(
        child: Scaffold(
          appBar: AppBar(title: const Text('Lounge preview')),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'A room for a quieter moment',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Explore the lounge concept using the numbered places '
                        'or the choices below. Activities use this sample session.',
                      ),
                      const SizedBox(height: 16),
                      _artwork(context),
                      const SizedBox(height: 8),
                      const Text('Concept artwork · Sample activities'),
                      const SizedBox(height: 16),
                      Text(
                        'Choose a place',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      for (var i = 0; i < _spots.length; i++)
                        _choice(context, _spots[i], i + 1),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          key: const ValueKey('lounge-reset'),
                          onPressed: () => setState(() => _selected = null),
                          icon: const Icon(Icons.refresh),
                          label: const Text('Reset room preview'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      KeyedSubtree(
                        key: _selectionAnchor,
                        child: _selection(context),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  Widget _artwork(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = width * 9 / 16;
          final showMarkers =
              width >= 600 && MediaQuery.textScalerOf(context).scale(16) <= 24;
          return Image.asset(
            widget.artworkAsset,
            key: const ValueKey('lounge-artwork'),
            fit: BoxFit.contain,
            cacheWidth: 1280,
            cacheHeight: 720,
            semanticLabel:
                'Lounge concept with sofas, a coffee table and a city window.',
            // The fallback is outside the fixed image ratio so enlarged text
            // remains readable in compact windows.
            errorBuilder: (_, __, ___) => const Card(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Lounge artwork is unavailable. '
                  'The room choices still work.',
                ),
              ),
            ),
            frameBuilder: (context, child, _, __) => ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child,
                    if (showMarkers)
                      for (var i = 0; i < _spots.length; i++)
                        Positioned(
                          left: _spots[i].position.dx * width - 24,
                          top: _spots[i].position.dy * height - 24,
                          width: 48,
                          height: 48,
                          child: Tooltip(
                            message: _spots[i].label,
                            excludeFromSemantics: true,
                            child: Semantics(
                              label: '${i + 1}. ${_spots[i].label}',
                              selected: _selected == _spots[i],
                              child: FilledButton(
                                key: ValueKey('lounge-marker-${_spots[i].id}'),
                                style: FilledButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  shape: const CircleBorder(),
                                ),
                                onPressed: () => _select(_spots[i]),
                                child:
                                    ExcludeSemantics(child: Text('${i + 1}')),
                              ),
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ),
          );
        },
      );

  Widget _choice(BuildContext context, _LoungeSpot spot, int number) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selected == spot;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        child: OutlinedButton(
          key: ValueKey('lounge-spot-${spot.id}'),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(16),
            backgroundColor: selected ? colors.primaryContainer : null,
            foregroundColor: selected ? colors.onPrimaryContainer : null,
          ),
          onPressed: () => _select(spot),
          child: Row(
            children: [
              Icon(spot.icon),
              const SizedBox(width: 12),
              Expanded(child: Text('$number. ${spot.label}')),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selection(BuildContext context) {
    final spot = _selected;
    if (spot == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Text('Choose a place in the lounge'),
        ),
      );
    }
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const ValueKey('lounge-selection'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(spot.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(spot.description),
              for (final example in spot.examples)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(example),
                ),
              if (spot.action != _LoungeAction.none)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: switch (spot.action) {
                    _LoungeAction.quietWriting => FilledButton(
                        key: const ValueKey('lounge-open-quiet-writing'),
                        onPressed: () => _open(widget.quietWritingBuilder),
                        child: const Text('Try quiet writing'),
                      ),
                    _LoungeAction.smallStep => FilledButton(
                        key: const ValueKey('lounge-open-small-step'),
                        onPressed: () => _open(widget.smallStepBuilder),
                        child: const Text('Try a small step'),
                      ),
                    _LoungeAction.settle => FilledButton(
                        key: const ValueKey('lounge-open-settle'),
                        onPressed: () => _open(widget.settleBuilder),
                        child: const Text('Try guided support'),
                      ),
                    _LoungeAction.none => const SizedBox.shrink(),
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}
