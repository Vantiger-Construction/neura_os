import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/windows_license_service.dart';

/// Public, shareable Stripe Payment Link -- not secret, safe as a plain
/// constant. Update this once the real Payment Link is created (see the
/// monetization plan for the exact `curl` command that sets its
/// after_completion redirect to the deployed verify-purchase function).
const String _kStripePaymentLinkUrl = 'https://buy.stripe.com/REPLACE_ME';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  final _codeController = TextEditingController();
  bool _redeeming = false;
  bool? _isPremium;

  @override
  void initState() {
    super.initState();
    _isPremium = WindowsLicenseService.instance.isPremium;
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _openPaymentLink() async {
    final uri = Uri.parse(_kStripePaymentLinkUrl);
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _redeem() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) return;

    setState(() => _redeeming = true);
    final ok = await WindowsLicenseService.instance.redeemCode(code);
    if (!mounted) return;

    setState(() {
      _redeeming = false;
      if (ok) _isPremium = true;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Premium unlocked. Thank you!'
              : "That code didn't check out. Double-check it, or try again in a few seconds if you just paid.",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Neura Premium')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: _isPremium == true ? _buildUnlocked() : _buildLocked(),
      ),
    );
  }

  Widget _buildUnlocked() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, size: 48, color: Colors.amber),
          SizedBox(height: 12),
          Text(
            '✓ Premium unlocked',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildLocked() {
    return ListView(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Neura Premium',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text('One-time purchase. Unlocked forever, this device.'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _openPaymentLink,
                    child: const Text('Buy on the web'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Already purchased?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                const Text(
                  'After paying, copy the code shown on the confirmation page and paste it below.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _codeController,
                  decoration: const InputDecoration(
                    labelText: 'Code',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _redeeming ? null : _redeem,
                    child: _redeeming
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Unlock'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
