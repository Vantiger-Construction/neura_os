import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../reliability/safe_boot.dart';
import 'camera_hawk_client.dart';

class CameraHawkScreen extends StatefulWidget {
  const CameraHawkScreen({super.key, this.client});
  final CameraHawkClient? client;
  @override
  State<CameraHawkScreen> createState() => _CameraHawkScreenState();
}

class _CameraHawkScreenState extends State<CameraHawkScreen>
    with WidgetsBindingObserver {
  late final _client = widget.client ?? CameraHawkClient();
  final _username = TextEditingController();
  final _password = TextEditingController();
  List<CameraHawkCamera> _cameras = [];
  bool _busy = false;
  bool _foreground = true;
  String? _message;
  int _generation = 0;

  bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  bool get _allowed =>
      _supported &&
      _foreground &&
      !SafeBoot.instance.safeMode.value &&
      !SafeBoot.instance.restartRequired.value;

  @override
  void initState() {
    super.initState();
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addObserver(this);
    SafeBoot.instance.safeMode.addListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.addListener(_onSafetyChanged);
  }

  void _onSafetyChanged() {
    if (!_allowed) _stop();
    if (mounted) setState(() {});
  }

  void _stop() {
    _generation++;
    _password.clear();
    _cameras = [];
    _message = null;
    _busy = false;
    unawaited(_client.disconnect());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _stop();
    if (mounted) setState(() {});
  }

  Future<void> _connect() async {
    if (!_allowed || _busy) return;
    final generation = _generation;
    setState(() {
      _busy = true;
      _message = null;
    });
    final password = _password.text;
    _password.clear();
    try {
      if (!_client.connected)
        await _client.signIn(_username.text.trim(), password);
      final cameras = await _client.cameras();
      if (mounted && _allowed && generation == _generation) {
        setState(() => _cameras = cameras);
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _message =
              'Could not connect. Start Camera Hawk on this PC and check your sign-in.',
        );
      }
    } finally {
      if (mounted && generation == _generation) setState(() => _busy = false);
    }
  }

  Future<void> _dashboard() async {
    if (!_allowed || _busy) return;
    try {
      final opened = await launchUrl(
        CameraHawkClient.dashboardUri,
        mode: LaunchMode.externalApplication,
      );
      if (!opened && mounted)
        setState(() => _message = 'Could not open the camera dashboard.');
    } catch (_) {
      if (mounted)
        setState(() => _message = 'Could not open the camera dashboard.');
    }
  }

  @override
  void dispose() {
    _generation++;
    WidgetsBinding.instance.removeObserver(this);
    SafeBoot.instance.safeMode.removeListener(_onSafetyChanged);
    SafeBoot.instance.restartRequired.removeListener(_onSafetyChanged);
    _username.dispose();
    _password.dispose();
    unawaited(_client.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Camera Hawk')),
        body: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const Text(
              'Your private camera center',
              style: TextStyle(fontSize: 24),
            ),
            const SizedBox(height: 12),
            const Text(
              'Start your Camera Hawk service on this Windows PC, then sign in to see registered cameras. Camera images stay outside Neura chat and memory.',
            ),
            if (!_supported)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'This connection currently requires Windows. Android remote access is not configured.',
                ),
              ),
            if (SafeBoot.instance.safeMode.value ||
                SafeBoot.instance.restartRequired.value)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  'Camera Hawk access is paused for Safe Mode or recovery.',
                ),
              ),
            if (!_client.connected) ...[
              TextField(
                controller: _username,
                enabled: _allowed && !_busy,
                autofillHints: const [],
                decoration: const InputDecoration(
                  labelText: 'Camera Hawk username',
                ),
              ),
              TextField(
                controller: _password,
                enabled: _allowed && !_busy,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                autofillHints: const [],
                decoration: const InputDecoration(labelText: 'Password'),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton(
                  onPressed: _allowed && !_busy ? _connect : null,
                  child: Text(
                    _busy
                        ? 'Connecting…'
                        : _client.connected
                            ? 'Refresh cameras'
                            : 'Sign in',
                  ),
                ),
                OutlinedButton(
                  onPressed: _allowed && !_busy ? _dashboard : null,
                  child: const Text('Open camera dashboard'),
                ),
                if (_client.connected)
                  TextButton(
                    onPressed: () {
                      _stop();
                      setState(() {});
                    },
                    child: const Text('Disconnect'),
                  ),
              ],
            ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'The dashboard opens in your browser and uses its own sign-in. Close it separately when finished; Neura Safe Mode does not stop the independent Camera Hawk service.',
              ),
            ),
            if (_message != null) Text(_message!),
            for (final camera in _cameras)
              ListTile(
                leading: const Icon(Icons.videocam_outlined),
                title: Text(camera.name),
                subtitle: Text(camera.location),
                trailing: Text(camera.enabled ? 'Enabled' : 'Disabled'),
              ),
            if (_client.connected && _cameras.isEmpty && !_busy)
              const Text(
                'No registered cameras. Add your cameras in the Camera Hawk dashboard.',
              ),
          ],
        ),
      );
}
