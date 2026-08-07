import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../../../screens/ambient_recordings_screen.dart';
import '../../../services/ambient_listening_prefs.dart';
import '../../../services/app_lock_prefs.dart';
import '../../../services/wake_word_prefs.dart';
import '../../../services/wake_word_listener_service.dart';
import 'data_controls_screen.dart';
import 'legal_text_screen.dart';
import 'privacy_texts.dart';

class PrivacyHomeScreen extends StatelessWidget {
  const PrivacyHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & Safety')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(child: _DeviceLockToggle()),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                const _AmbientListeningToggle(),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.mic_none_outlined),
                  title: const Text('View recorded clips'),
                  subtitle: const Text('Play back or delete what Neura has recorded.'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AmbientRecordingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Card(child: _WakeWordToggle()),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const Text('Privacy Policy'),
                  subtitle: const Text('How your data is stored and shared.'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalTextScreen(
                        title: 'Privacy Policy',
                        text: PrivacyTexts.privacyPolicy,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Terms of Service'),
                  subtitle: const Text('Rules, limits, and responsibilities.'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalTextScreen(
                        title: 'Terms of Service',
                        text: PrivacyTexts.termsOfService,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.health_and_safety_outlined),
                  title: const Text('Safety Disclaimer'),
                  subtitle: const Text('Important health and crisis guidance.'),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LegalTextScreen(
                        title: 'Safety Disclaimer',
                        text: PrivacyTexts.disclaimer,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_backup_restore),
              title: const Text('Data Controls'),
              subtitle: const Text('Export, import, or delete your local data.'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const DataControlsScreen()),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Pro tip: Legacy Vault lives on-device unless you export it.\n'
              'If you uninstall the app or lose the device, you can lose those capsules unless you keep an export somewhere safe.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          )
        ],
      ),
    );
  }
}

/// "Require device authentication to open Neura" toggle.
///
/// Only allows enabling once [LocalAuthentication.isDeviceSupported]
/// confirms the device actually has a usable auth method (biometrics or
/// PIN/password) — otherwise a user could lock themselves out with no way
/// back in short of clearing app data.
class _DeviceLockToggle extends StatefulWidget {
  const _DeviceLockToggle();

  @override
  State<_DeviceLockToggle> createState() => _DeviceLockToggleState();
}

class _DeviceLockToggleState extends State<_DeviceLockToggle> {
  final _auth = LocalAuthentication();
  bool? _deviceSupported;

  @override
  void initState() {
    super.initState();
    _auth.isDeviceSupported().then((supported) {
      if (mounted) setState(() => _deviceSupported = supported);
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppLockPrefsController.instance.enabled,
      builder: (context, enabled, _) {
        final checking = _deviceSupported == null;
        final supported = _deviceSupported ?? false;
        return SwitchListTile(
          value: enabled,
          onChanged: checking || !supported
              ? null
              : (v) => AppLockPrefsController.instance.setEnabled(v),
          secondary: const Icon(Icons.lock_person_outlined),
          title: const Text('Require device lock to open Neura'),
          subtitle: Text(
            checking
                ? 'Checking device support…'
                : supported
                    ? 'Uses your Windows PIN/password or biometrics. Off by default.'
                    : 'Not available — this device has no PIN, password, or biometrics set up.',
          ),
        );
      },
    );
  }
}

/// "Listen for speech and record short clips" toggle.
///
/// Off by default. When on, Neura's mic activates only when it hears
/// speech (not continuously/indiscriminately) and saves a short encrypted
/// clip; a visible indicator shows whenever a clip is actively being
/// recorded (see AmbientRecordingBadge), and turning this off immediately
/// stops it.
class _AmbientListeningToggle extends StatelessWidget {
  const _AmbientListeningToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AmbientListeningPrefsController.instance.enabled,
      builder: (context, enabled, _) {
        return SwitchListTile(
          value: enabled,
          onChanged: (v) => AmbientListeningPrefsController.instance.setEnabled(v),
          secondary: const Icon(Icons.hearing_outlined),
          title: const Text('Listen for speech and record clips'),
          subtitle: const Text(
            'Records short encrypted clips when it hears you talking. Off by default. '
            'A visible indicator shows whenever it\'s actively recording.',
          ),
        );
      },
    );
  }
}

/// "Hey Neura" hands-free wake phrase toggle.
///
/// Off by default. When on, Neura continuously transcribes speech (a
/// different privacy model from the raw-audio clip recording above) and,
/// once she hears "Hey Neura", sends whatever follows to the AI and speaks
/// the reply -- a full chat turn, hands-free.
class _WakeWordToggle extends StatelessWidget {
  const _WakeWordToggle();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: WakeWordPrefsController.instance.enabled,
      builder: (context, enabled, _) {
        return SwitchListTile(
          value: enabled,
          onChanged: (v) async {
            await WakeWordPrefsController.instance.setEnabled(v);
            if (v) {
              await WakeWordListenerService.instance.start();
            } else {
              await WakeWordListenerService.instance.stop();
            }
          },
          secondary: const Icon(Icons.record_voice_over_outlined),
          title: const Text('"Hey Neura" hands-free wake phrase'),
          subtitle: const Text(
            'Continuously listens for "Hey Neura" and starts a spoken conversation '
            'when she hears it. Off by default.',
          ),
        );
      },
    );
  }
}
