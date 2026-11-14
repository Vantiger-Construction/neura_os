import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'neura_demo_app.dart';

const neuraDemoBuild = bool.fromEnvironment('NEURA_DEMO');

/// No production startup or error-vault handler is entered, even on failure.
void runNeuraDemo() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NeuraDemoBootstrap());
}

class NeuraDemoBootstrap extends StatefulWidget {
  const NeuraDemoBootstrap({super.key, this.verifyIsolation});
  final Future<bool> Function()? verifyIsolation;

  @override
  State<NeuraDemoBootstrap> createState() => _NeuraDemoBootstrapState();
}

Future<bool> verifyNativeDemoIsolation() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.windows) return false;
  const channel = MethodChannel('neura/isolated_preview');
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final token = await channel
          .invokeMethod<String>('getIsolation')
          .timeout(const Duration(milliseconds: 600));
      return token == 'sample-data-no-plugins-v1';
    } catch (_) {
      if (attempt < 2) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
  }
  return false;
}

class _NeuraDemoBootstrapState extends State<NeuraDemoBootstrap> {
  bool? _isolated;
  @override
  void initState() {
    super.initState();
    _verify();
  }

  Future<void> _verify() async {
    bool isolated;
    try {
      isolated = await (widget.verifyIsolation ?? verifyNativeDemoIsolation)()
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      isolated = false;
    }
    if (mounted) setState(() => _isolated = isolated);
  }

  @override
  Widget build(BuildContext context) => _isolated == true
      ? const NeuraDemoApp()
      : MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_isolated == null
                        ? 'Checking the isolated preview host…'
                        : 'Preview unavailable. The isolated Windows host could not be verified. '
                            'The sample session was not opened. Rebuild with NEURA_DEMO=true.'))),
          ));
}
