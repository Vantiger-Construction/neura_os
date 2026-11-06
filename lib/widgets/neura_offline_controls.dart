import 'package:flutter/material.dart';

import '../services/neura_offline_budget.dart';
import '../services/neura_generation_cancel.dart';
import '../services/neura_ollama_chat.dart';
import '../reliability/safe_boot.dart';
import '../startup/neura_error_pipeline.dart';

class NeuraOfflineControls extends StatefulWidget {
  const NeuraOfflineControls({super.key, required this.budget, this.readiness});
  final NeuraOfflineBudget budget;

  /// Borrowed test seam; production owns a short-lived diagnostic adapter.
  final NeuraOllamaChat? readiness;

  @override
  State<NeuraOfflineControls> createState() => _NeuraOfflineControlsState();
}

class _NeuraOfflineControlsState extends State<NeuraOfflineControls>
    with WidgetsBindingObserver {
  late NeuraOfflineBudget _budget;
  String? _memory;
  bool _checking = false;
  int _serial = 0;
  late final NeuraOllamaChat _readiness;
  NeuraGenerationCancel? _checkCancel;
  NeuraOllamaReadiness? _report;
  String? _readinessMessage;
  bool _blocked = false;

  @override
  void initState() {
    super.initState();
    _budget = widget.budget;
    _readiness = widget.readiness ?? NeuraOllamaChat();
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.addListener(_onSafetyChanged);
    NeuraErrorPipeline.instance.fatalError.addListener(_onSafetyChanged);
    _onSafetyChanged();
  }

  void _onSafetyChanged() {
    if (!SafeBoot.instance.safeMode.value &&
        !SafeBoot.instance.restartRequired.value &&
        NeuraErrorPipeline.instance.fatalError.value == null) {
      return;
    }
    _blocked = true;
    _cancelCheck(
      'Readiness check blocked by Safe Mode or recovery. Restart Neura before checking again.',
    );
  }

  void _cancelCheck(String? message) {
    ++_serial;
    _checkCancel?.cancel();
    _checkCancel = null;
    if (!mounted) return;
    setState(() {
      _checking = false;
      _report = null;
      _memory = null;
      _readinessMessage = message;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _cancelCheck(
        'Check cleared when Neura left the foreground. Check again when ready.',
      );
    }
  }

  @override
  void dispose() {
    ++_serial;
    _checkCancel?.cancel();
    if (widget.readiness == null) _readiness.dispose();
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_onSafetyChanged);
    NeuraErrorPipeline.instance.fatalError.removeListener(_onSafetyChanged);
    super.dispose();
  }

  Future<void> _check() async {
    if (_blocked || _checking) return;
    final serial = ++_serial;
    setState(() {
      _checking = true;
      _report = null;
      _readinessMessage = null;
      _memory = null;
    });
    final value = await NeuraOfflineMemory.read();
    if (!mounted || serial != _serial) return;
    setState(() {
      _checking = false;
      _memory = value == null
          ? 'RAM check unavailable. Windows checks memory again before each reply.'
          : '${value.availableMiB} MiB available of ${value.totalMiB} MiB. '
              '${value.admitted ? 'Meets the RAM floor at this moment.' : 'Below the RAM floor. Close other apps before trying again.'} '
              'This does not verify Ollama or model readiness.';
    });
  }

  Future<void> _checkReadiness() async {
    if (_blocked || _checking) return;
    final serial = ++_serial;
    final cancel = NeuraGenerationCancel('offline-readiness-$serial');
    _checkCancel = cancel;
    setState(() {
      _checking = true;
      _report = null;
      _memory = null;
      _readinessMessage = 'Checking local prerequisites…';
    });
    NeuraOllamaReadiness? report;
    String? message;
    try {
      report = await _readiness.checkReadiness(cancel: cancel);
    } on NeuraGenerationCancelled {
      message = 'Readiness check cancelled. Check again when ready.';
    } on StateError catch (error) {
      message = error.message.toString();
    }
    if (!mounted || serial != _serial) return;
    setState(() {
      _checking = false;
      _checkCancel = null;
      _report = report;
      _readinessMessage = message;
    });
  }

  Widget _readinessResults(NeuraOllamaReadiness report) {
    final memory = report.memory;
    final model = switch (report.model) {
      NeuraOllamaModelReadiness.unchecked =>
        'Not checked. Resolve Ollama availability and version first.',
      NeuraOllamaModelReadiness.verified =>
        'Verified local qwen3:4b-instruct: reviewed manifest, Qwen3 4.0B, Q4_K_M.',
      NeuraOllamaModelReadiness.notInstalled =>
        'Required model is missing. Install it yourself in PowerShell: ollama pull qwen3:4b-instruct',
      NeuraOllamaModelReadiness.remote =>
        'Remote model rejected. Install the required local qwen3:4b-instruct model explicitly.',
      NeuraOllamaModelReadiness.mismatch =>
        'Model identity differs from the reviewed qwen3:4b-instruct manifest or Qwen3 4.0B / Q4_K_M metadata. Review the local installation before retrying.',
      NeuraOllamaModelReadiness.malformed =>
        'Model metadata could not be verified. Check or update your local Ollama installation, then retry.',
      NeuraOllamaModelReadiness.unreachable =>
        'Ollama stopped responding during model verification. Open Ollama locally, then retry.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          report.ready
              ? 'Offline prerequisites met at this moment.'
              : 'Offline prerequisites are incomplete.',
        ),
        const SizedBox(height: 8),
        Text(
          report.daemonAvailable
              ? 'Ollama: available on this computer.'
              : 'Ollama: unavailable. Install and open Ollama yourself using its default local listener.',
        ),
        Text(
          'Version: ${report.versionSupported == null ? 'Not checked until Ollama is available.' : report.versionSupported! ? 'Supported stable release (requires 0.18.0 or newer).' : 'Unsupported or invalid. Update Ollama to a stable release, 0.18.0 or newer.'}',
        ),
        Text('Model: $model'),
        Text(
          memory == null
              ? 'RAM: unavailable. Memory admission cannot be confirmed.'
              : 'RAM: ${memory.availableMiB} MiB available of ${memory.totalMiB} MiB. ${memory.admitted ? 'Meets the 7 GiB total / 3.5 GiB available floor.' : 'Below the 7 GiB total / 3.5 GiB available floor. Close other apps; a machine with less than 7 GiB usable total RAM cannot use this model.'}',
        ),
        const SizedBox(height: 8),
        const Text(
          'This is a snapshot. Each reply checks again. Test your microphone, speaker, response speed and conversation quality separately. To speak, select Companion and After reply, then start Talk freely yourself.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Offline conversation controls'),
        scrollable: true,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Qwen3 4B stays selected. Compact retains less recent text; '
              'it does not reduce the model’s base RAM requirement. '
              'The Windows floor is 7 GiB total and 3.5 GiB available. '
              'No downloads or cloud fallback.',
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<NeuraOfflineBudget>(
              initialValue: _budget,
              decoration: const InputDecoration(labelText: 'Recent context'),
              items: [
                for (final budget in NeuraOfflineBudget.values)
                  DropdownMenuItem(
                    value: budget,
                    child: Text(
                      '${budget.label} · ${budget.contextBytes} UTF-8 bytes',
                    ),
                  ),
              ],
              onChanged: (value) {
                if (value != null) setState(() => _budget = value);
              },
            ),
            TextButton(
              onPressed: _checking || _blocked ? null : _check,
              child: Text(_checking ? 'Checking…' : 'Check available RAM'),
            ),
            if (_memory != null) Text(_memory!),
            const Divider(),
            const Text(
              'Check offline prerequisites before speaking. This only reads local model metadata and RAM; it does not load a model, download anything or turn on the microphone.',
            ),
            TextButton(
              onPressed: _checking || _blocked ? null : _checkReadiness,
              child: const Text('Check offline readiness'),
            ),
            if (_readinessMessage != null) Text(_readinessMessage!),
            if (_report != null) _readinessResults(_report!),
            if (_checking)
              TextButton(
                onPressed: () => _cancelCheck(
                  'Readiness check cancelled. Check again when ready.',
                ),
                child: const Text('Cancel check'),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, _budget),
            child: const Text('Apply'),
          ),
        ],
      );
}
