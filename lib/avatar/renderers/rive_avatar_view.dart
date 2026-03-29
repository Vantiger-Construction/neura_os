import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rive/rive.dart';

import '../avatar_asset.dart';
import '../avatar_controller.dart';
import '../avatar_types.dart';

class RiveAvatarView extends StatefulWidget {
  final AvatarSpec spec;
  final AvatarController controller;
  final double size;
  final BoxFit fit;
  final Widget fallback;

  const RiveAvatarView({
    super.key,
    required this.spec,
    required this.controller,
    this.size = 128,
    this.fit = BoxFit.contain,
    required this.fallback,
  });

  @override
  State<RiveAvatarView> createState() => _RiveAvatarViewState();
}

class _RiveLoaded {
  final Artboard artboard;
  final Map<String, SMIInput<dynamic>> inputs;

  _RiveLoaded(this.artboard, this.inputs);
}

class _RiveAvatarViewState extends State<RiveAvatarView> {
  Future<_RiveLoaded>? _loadFuture;
  AvatarSignals _prev = const AvatarSignals();

  @override
  void initState() {
    super.initState();
    _loadFuture = _load();
    widget.controller.addListener(_onSignals);
  }

  @override
  void didUpdateWidget(covariant RiveAvatarView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec.assetPath != widget.spec.assetPath ||
        oldWidget.spec.rive?.artboard != widget.spec.rive?.artboard ||
        oldWidget.spec.rive?.stateMachine != widget.spec.rive?.stateMachine) {
      _loadFuture = _load();
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onSignals);
      widget.controller.addListener(_onSignals);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onSignals);
    super.dispose();
  }

  void _onSignals() {
    // Just trigger rebuild to allow FutureBuilder to apply on success.
    // (We do direct input mutation below once loaded.)
    if (mounted) setState(() {});
  }

  Future<_RiveLoaded> _load() async {
    final data = await rootBundle.load(widget.spec.assetPath);
    final bytes = data.buffer.asUint8List();
    final file =
        RiveFile.import(ByteData.sublistView(Uint8List.fromList(bytes)));

    final cfg = widget.spec.rive;
    final Artboard artboard = (cfg?.artboard != null)
        ? (file.artboardByName(cfg!.artboard!) ?? file.mainArtboard)
        : file.mainArtboard;

    final inputs = <String, SMIInput<dynamic>>{};

    final smName = cfg?.stateMachine;
    if (smName != null && smName.trim().isNotEmpty) {
      final controller = StateMachineController.fromArtboard(artboard, smName);
      if (controller != null) {
        artboard.addController(controller);

        // Bind inputs. Missing inputs are ignored on purpose.
        final mapping = cfg?.inputNames ?? const <String, String>{};
        for (final wish in [
          AvatarRiveInputs.isListening,
          AvatarRiveInputs.isTalking,
          AvatarRiveInputs.isThinking,
          AvatarRiveInputs.isError,
          AvatarRiveInputs.mood,
          AvatarRiveInputs.energy,
          AvatarRiveInputs.wave,
          AvatarRiveInputs.blink,
        ]) {
          final actualName = mapping[wish] ?? wish;
          final input = controller.findInput<dynamic>(actualName);
          if (input != null) {
            inputs[wish] = input;
          }
        }
      }
    }

    return _RiveLoaded(artboard, inputs);
  }

  void _applySignals(_RiveLoaded loaded, AvatarSignals s) {
    void setBool(String key, bool v) {
      final input = loaded.inputs[key];
      if (input is SMIBool) input.value = v;
    }

    void setNumber(String key, double v) {
      final input = loaded.inputs[key];
      if (input is SMINumber) input.value = v;
    }

    void fire(String key) {
      final input = loaded.inputs[key];
      if (input is SMITrigger) input.fire();
    }

    setBool(AvatarRiveInputs.isListening, s.isListening);
    setBool(AvatarRiveInputs.isTalking, s.isTalking);
    setBool(AvatarRiveInputs.isThinking, s.isThinking);
    setBool(AvatarRiveInputs.isError, s.isError);
    setNumber(AvatarRiveInputs.mood, s.mood);
    setNumber(AvatarRiveInputs.energy, s.energy);

    // Rising-edge triggers.
    if (s.wave && !_prev.wave) fire(AvatarRiveInputs.wave);
    if (s.blink && !_prev.blink) fire(AvatarRiveInputs.blink);

    _prev = s;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: FutureBuilder<_RiveLoaded>(
        future: _loadFuture,
        builder: (context, snap) {
          if (snap.hasError) {
            return widget.fallback;
          }
          if (!snap.hasData) {
            return const Center(
                child: CircularProgressIndicator(strokeWidth: 2));
          }

          final loaded = snap.data!;
          _applySignals(loaded, widget.controller.signals);

          return Rive(
            artboard: loaded.artboard,
            fit: widget.fit,
          );
        },
      ),
    );
  }
}
