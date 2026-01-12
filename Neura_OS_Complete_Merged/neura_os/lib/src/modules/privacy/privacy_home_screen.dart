import 'package:flutter/material.dart';

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
