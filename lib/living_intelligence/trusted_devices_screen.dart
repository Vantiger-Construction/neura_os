import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../services/neura_device_continuity_service.dart';
import '../services/neura_device_identity_service.dart';
import 'device_continuity.dart';

/// Manages which other devices this one trusts, using the real pairing
/// policy kernel in device_continuity.dart with real Ed25519 device
/// identities.
///
/// Honest scope note: there is no automatic network/Bluetooth channel
/// between devices in this app yet, so the pairing "code" here travels
/// manually - shared as text (share sheet, copy/paste, read aloud) rather
/// than sent automatically. This screen manages *trust*, not data sync:
/// no memory, preferences, or other content actually moves between devices
/// yet. Confirming a fingerprint by eye before adding a device is a real,
/// standard verification step (the same pattern linked-device features in
/// other apps use), not a placeholder.
class TrustedDevicesScreen extends StatefulWidget {
  const TrustedDevicesScreen({super.key});

  @override
  State<TrustedDevicesScreen> createState() => _TrustedDevicesScreenState();
}

class _TrustedDevicesScreenState extends State<TrustedDevicesScreen> {
  final _identity = NeuraDeviceIdentityService.instance;
  final _continuity = NeuraDeviceContinuityService.instance;
  bool _ready = false;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      await _identity.ensureLoaded();
      _continuity.ensureLoaded();
      if (mounted) setState(() => _ready = true);
    } catch (error) {
      if (mounted) setState(() => _loadError = error);
    }
  }

  Future<void> _editDisplayName() async {
    final controller = TextEditingController(text: _identity.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('This device\'s name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Shown to devices you pair with',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await _identity.setDisplayName(name);
      if (mounted) setState(() {});
    }
  }

  Future<void> _revoke(NeuraDeviceIdentity device) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove this device?'),
        content: Text(
          '${device.displayName} will no longer be trusted. You can pair '
          'it again later if you want to.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _continuity.revokeDevice(device.deviceId);
      if (mounted) setState(() {});
    }
  }

  Future<void> _showMyPairingCode() async {
    final session = _continuity.registry.beginPairing(
      deviceId: _identity.deviceId,
    );
    final blob = _PairingBlob(
      deviceId: _identity.deviceId,
      displayName: _identity.displayName,
      publicKeyFingerprint: _identity.fingerprint,
      code: session.code,
      expiresAtUtc: session.expiresAtUtc,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => _MyPairingCodeDialog(blob: blob),
    );
  }

  Future<void> _addDeviceFromCode() async {
    final device = await showDialog<_PairedDeviceInput>(
      context: context,
      builder: (context) => const _AddDeviceDialog(),
    );
    if (device == null || !mounted) return;
    if (device.blob.deviceId == _identity.deviceId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This code belongs to this device.')),
      );
      return;
    }
    try {
      await _continuity.pairDevice(
        identity: NeuraDeviceIdentity(
          deviceId: device.blob.deviceId,
          displayName: device.blob.displayName,
          publicKeyFingerprint: device.blob.publicKeyFingerprint,
        ),
        policy: NeuraDeviceSyncPolicy(
          allowedCategories: device.allowedCategories,
          allowCloudRelay: false,
        ),
        directUserGesture: true,
        fingerprintVerified: device.fingerprintConfirmed,
      );
      if (mounted) setState(() {});
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not add device: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trusted Devices')),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loadError != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Could not load device identity: $_loadError'),
        ),
      );
    }
    if (!_ready) {
      return const Center(child: CircularProgressIndicator());
    }

    final devices =
        _continuity.devices.where((device) => !device.revoked).toList();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Manages which devices Neura trusts. There is no automatic sync '
          'channel yet, so pairing codes travel manually (share, paste, or '
          'read aloud) rather than over the network.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        Card(
          child: ListTile(
            leading: const Icon(Icons.smartphone_outlined),
            title: Text(_identity.displayName),
            subtitle: Text('This device • ${_identity.fingerprint}'),
            trailing: IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Rename this device',
              onPressed: _editDisplayName,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            FilledButton.icon(
              onPressed: _showMyPairingCode,
              icon: const Icon(Icons.qr_code_outlined),
              label: const Text('Show my pairing code'),
            ),
            OutlinedButton.icon(
              onPressed: _addDeviceFromCode,
              icon: const Icon(Icons.add_link_outlined),
              label: const Text('Add a device from a code'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Trusted devices', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 6),
        if (devices.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.devices_other_outlined),
              title: Text('No other devices yet'),
              subtitle: Text(
                'Pair a device to start building a trust relationship '
                'between them.',
              ),
            ),
          )
        else
          ...devices.map(
            (device) => Card(
              child: ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: Text(device.displayName),
                subtitle: Text(
                  '${device.publicKeyFingerprint}\n'
                  '${_categoriesSummary(device.deviceId)}',
                ),
                isThreeLine: true,
                trailing: IconButton(
                  icon: const Icon(Icons.link_off),
                  tooltip: 'Remove',
                  onPressed: () => _revoke(device),
                ),
              ),
            ),
          ),
      ],
    );
  }

  String _categoriesSummary(String deviceId) {
    final categories = _continuity.policyFor(deviceId)?.allowedCategories;
    if (categories == null || categories.isEmpty) {
      return 'No categories allowed yet';
    }
    return categories.map((category) => category.name).join(', ');
  }
}

class _PairingBlob {
  const _PairingBlob({
    required this.deviceId,
    required this.displayName,
    required this.publicKeyFingerprint,
    required this.code,
    required this.expiresAtUtc,
  });

  final String deviceId;
  final String displayName;
  final String publicKeyFingerprint;
  final String code;
  final DateTime expiresAtUtc;

  bool get isExpired => !DateTime.now().toUtc().isBefore(expiresAtUtc);

  String encode() {
    final json = jsonEncode({
      'v': 1,
      'deviceId': deviceId,
      'displayName': displayName,
      'publicKeyFingerprint': publicKeyFingerprint,
      'code': code,
      'expiresAt': expiresAtUtc.toIso8601String(),
    });
    return base64Encode(utf8.encode(json));
  }

  static final RegExp _deviceIdPattern = RegExp(r'^[A-Za-z0-9_-]{16,128}
}

class _MyPairingCodeDialog extends StatefulWidget {
  const _MyPairingCodeDialog({required this.blob});

  final _PairingBlob blob;

  @override
  State<_MyPairingCodeDialog> createState() => _MyPairingCodeDialogState();
}

class _MyPairingCodeDialogState extends State<_MyPairingCodeDialog> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = widget.blob;
    final remaining = blob.expiresAtUtc.difference(DateTime.now().toUtc());
    final encoded = blob.encode();

    return AlertDialog(
      title: const Text('Your pairing code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send this code to the other device (message, email, or read '
              'it aloud). On that device, choose "Add a device from a code" '
              'and paste it in.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              blob.code,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            Text('Fingerprint: ${blob.publicKeyFingerprint}'),
            const SizedBox(height: 4),
            Text(
              remaining.isNegative
                  ? 'Expired — reopen this to get a new code.'
                  : 'Expires in ${remaining.inMinutes}m ${remaining.inSeconds % 60}s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: encoded));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pairing code copied')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy'),
        ),
        TextButton.icon(
          onPressed: () => unawaited(Share.share(encoded)),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _PairedDeviceInput {
  const _PairedDeviceInput({
    required this.blob,
    required this.fingerprintConfirmed,
    required this.allowedCategories,
  });

  final _PairingBlob blob;
  final bool fingerprintConfirmed;
  final Set<NeuraContinuityCategory> allowedCategories;
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog();

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _controller = TextEditingController();
  _PairingBlob? _blob;
  String? _parseError;
  bool _fingerprintConfirmed = false;
  final Set<NeuraContinuityCategory> _categories = {
    NeuraContinuityCategory.preferences,
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final blob = _PairingBlob.tryParse(_controller.text);
    setState(() {
      _blob = blob;
      _parseError =
          blob == null ? 'That doesn\'t look like a valid code.' : null;
      _fingerprintConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blob = _blob;
    return AlertDialog(
      title: const Text('Add a device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Paste the pairing code',
                errorText: _parseError,
              ),
              onChanged: (_) => _parse(),
            ),
            if (blob != null) ...[
              const SizedBox(height: 16),
              Text(
                blob.isExpired
                    ? 'This code has expired — ask for a new one.'
                    : 'From: ${blob.displayName}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('Confirmation code: ${blob.code}'),
              const SizedBox(height: 4),
              Text('Fingerprint: ${blob.publicKeyFingerprint}'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _fingerprintConfirmed,
                onChanged: blob.isExpired
                    ? null
                    : (value) =>
                        setState(() => _fingerprintConfirmed = value ?? false),
                title: const Text(
                  'This fingerprint matches what\'s shown on the other device',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow syncing for:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                spacing: 8,
                children: NeuraContinuityCategory.values
                    .map(
                      (category) => FilterChip(
                        label: Text(category.name),
                        selected: _categories.contains(category),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _categories.add(category);
                          } else {
                            _categories.remove(category);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: blob == null ||
                  blob.isExpired ||
                  !_fingerprintConfirmed ||
                  _categories.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _PairedDeviceInput(
                      blob: blob,
                      fingerprintConfirmed: _fingerprintConfirmed,
                      allowedCategories: _categories,
                    ),
                  ),
          child: const Text('Add device'),
        ),
      ],
    );
  }
}
);
  static final RegExp _fingerprintPattern =
      RegExp(r'^[0-9A-F]{4}(?:-[0-9A-F]{4}){3}
}

class _MyPairingCodeDialog extends StatefulWidget {
  const _MyPairingCodeDialog({required this.blob});

  final _PairingBlob blob;

  @override
  State<_MyPairingCodeDialog> createState() => _MyPairingCodeDialogState();
}

class _MyPairingCodeDialogState extends State<_MyPairingCodeDialog> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = widget.blob;
    final remaining = blob.expiresAtUtc.difference(DateTime.now().toUtc());
    final encoded = blob.encode();

    return AlertDialog(
      title: const Text('Your pairing code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send this code to the other device (message, email, or read '
              'it aloud). On that device, choose "Add a device from a code" '
              'and paste it in.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              blob.code,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            Text('Fingerprint: ${blob.publicKeyFingerprint}'),
            const SizedBox(height: 4),
            Text(
              remaining.isNegative
                  ? 'Expired — reopen this to get a new code.'
                  : 'Expires in ${remaining.inMinutes}m ${remaining.inSeconds % 60}s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: encoded));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pairing code copied')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy'),
        ),
        TextButton.icon(
          onPressed: () => unawaited(Share.share(encoded)),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _PairedDeviceInput {
  const _PairedDeviceInput({
    required this.blob,
    required this.fingerprintConfirmed,
    required this.allowedCategories,
  });

  final _PairingBlob blob;
  final bool fingerprintConfirmed;
  final Set<NeuraContinuityCategory> allowedCategories;
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog();

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _controller = TextEditingController();
  _PairingBlob? _blob;
  String? _parseError;
  bool _fingerprintConfirmed = false;
  final Set<NeuraContinuityCategory> _categories = {
    NeuraContinuityCategory.preferences,
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final blob = _PairingBlob.tryParse(_controller.text);
    setState(() {
      _blob = blob;
      _parseError =
          blob == null ? 'That doesn\'t look like a valid code.' : null;
      _fingerprintConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blob = _blob;
    return AlertDialog(
      title: const Text('Add a device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Paste the pairing code',
                errorText: _parseError,
              ),
              onChanged: (_) => _parse(),
            ),
            if (blob != null) ...[
              const SizedBox(height: 16),
              Text(
                blob.isExpired
                    ? 'This code has expired — ask for a new one.'
                    : 'From: ${blob.displayName}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('Fingerprint: ${blob.publicKeyFingerprint}'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _fingerprintConfirmed,
                onChanged: blob.isExpired
                    ? null
                    : (value) =>
                        setState(() => _fingerprintConfirmed = value ?? false),
                title: const Text(
                  'This fingerprint matches what\'s shown on the other device',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow syncing for:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                spacing: 8,
                children: NeuraContinuityCategory.values
                    .map(
                      (category) => FilterChip(
                        label: Text(category.name),
                        selected: _categories.contains(category),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _categories.add(category);
                          } else {
                            _categories.remove(category);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: blob == null ||
                  blob.isExpired ||
                  !_fingerprintConfirmed ||
                  _categories.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _PairedDeviceInput(
                      blob: blob,
                      fingerprintConfirmed: _fingerprintConfirmed,
                      allowedCategories: _categories,
                    ),
                  ),
          child: const Text('Add device'),
        ),
      ],
    );
  }
}
);
  static final RegExp _codePattern = RegExp(r'^\d{6}
}

class _MyPairingCodeDialog extends StatefulWidget {
  const _MyPairingCodeDialog({required this.blob});

  final _PairingBlob blob;

  @override
  State<_MyPairingCodeDialog> createState() => _MyPairingCodeDialogState();
}

class _MyPairingCodeDialogState extends State<_MyPairingCodeDialog> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = widget.blob;
    final remaining = blob.expiresAtUtc.difference(DateTime.now().toUtc());
    final encoded = blob.encode();

    return AlertDialog(
      title: const Text('Your pairing code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send this code to the other device (message, email, or read '
              'it aloud). On that device, choose "Add a device from a code" '
              'and paste it in.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              blob.code,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            Text('Fingerprint: ${blob.publicKeyFingerprint}'),
            const SizedBox(height: 4),
            Text(
              remaining.isNegative
                  ? 'Expired — reopen this to get a new code.'
                  : 'Expires in ${remaining.inMinutes}m ${remaining.inSeconds % 60}s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: encoded));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pairing code copied')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy'),
        ),
        TextButton.icon(
          onPressed: () => unawaited(Share.share(encoded)),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _PairedDeviceInput {
  const _PairedDeviceInput({
    required this.blob,
    required this.fingerprintConfirmed,
    required this.allowedCategories,
  });

  final _PairingBlob blob;
  final bool fingerprintConfirmed;
  final Set<NeuraContinuityCategory> allowedCategories;
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog();

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _controller = TextEditingController();
  _PairingBlob? _blob;
  String? _parseError;
  bool _fingerprintConfirmed = false;
  final Set<NeuraContinuityCategory> _categories = {
    NeuraContinuityCategory.preferences,
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final blob = _PairingBlob.tryParse(_controller.text);
    setState(() {
      _blob = blob;
      _parseError =
          blob == null ? 'That doesn\'t look like a valid code.' : null;
      _fingerprintConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blob = _blob;
    return AlertDialog(
      title: const Text('Add a device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Paste the pairing code',
                errorText: _parseError,
              ),
              onChanged: (_) => _parse(),
            ),
            if (blob != null) ...[
              const SizedBox(height: 16),
              Text(
                blob.isExpired
                    ? 'This code has expired — ask for a new one.'
                    : 'From: ${blob.displayName}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('Fingerprint: ${blob.publicKeyFingerprint}'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _fingerprintConfirmed,
                onChanged: blob.isExpired
                    ? null
                    : (value) =>
                        setState(() => _fingerprintConfirmed = value ?? false),
                title: const Text(
                  'This fingerprint matches what\'s shown on the other device',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow syncing for:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                spacing: 8,
                children: NeuraContinuityCategory.values
                    .map(
                      (category) => FilterChip(
                        label: Text(category.name),
                        selected: _categories.contains(category),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _categories.add(category);
                          } else {
                            _categories.remove(category);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: blob == null ||
                  blob.isExpired ||
                  !_fingerprintConfirmed ||
                  _categories.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _PairedDeviceInput(
                      blob: blob,
                      fingerprintConfirmed: _fingerprintConfirmed,
                      allowedCategories: _categories,
                    ),
                  ),
          child: const Text('Add device'),
        ),
      ],
    );
  }
}
);

  static _PairingBlob? tryParse(String text) {
    final encoded = text.trim();
    if (encoded.isEmpty || encoded.length > 2048) return null;
    try {
      final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
      if (decoded is! Map<String, dynamic> || decoded['v'] != 1) return null;

      final deviceId = decoded['deviceId'];
      final displayName = decoded['displayName'];
      final fingerprint = decoded['publicKeyFingerprint'];
      final code = decoded['code'];
      final expiresAtText = decoded['expiresAt'];
      if (deviceId is! String ||
          !_deviceIdPattern.hasMatch(deviceId) ||
          displayName is! String ||
          displayName.trim().isEmpty ||
          displayName.length > 80 ||
          fingerprint is! String ||
          !_fingerprintPattern.hasMatch(fingerprint) ||
          code is! String ||
          !_codePattern.hasMatch(code) ||
          expiresAtText is! String) {
        return null;
      }

      final expiresAt = DateTime.parse(expiresAtText).toUtc();
      final now = DateTime.now().toUtc();
      if (!now.isBefore(expiresAt) ||
          expiresAt.isAfter(now.add(const Duration(minutes: 10)))) {
        return null;
      }
      return _PairingBlob(
        deviceId: deviceId,
        displayName: displayName.trim(),
        publicKeyFingerprint: fingerprint,
        code: code,
        expiresAtUtc: expiresAt,
      );
    } catch (_) {
      return null;
    }
  }
}

class _MyPairingCodeDialog extends StatefulWidget {
  const _MyPairingCodeDialog({required this.blob});

  final _PairingBlob blob;

  @override
  State<_MyPairingCodeDialog> createState() => _MyPairingCodeDialogState();
}

class _MyPairingCodeDialogState extends State<_MyPairingCodeDialog> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final blob = widget.blob;
    final remaining = blob.expiresAtUtc.difference(DateTime.now().toUtc());
    final encoded = blob.encode();

    return AlertDialog(
      title: const Text('Your pairing code'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Send this code to the other device (message, email, or read '
              'it aloud). On that device, choose "Add a device from a code" '
              'and paste it in.',
            ),
            const SizedBox(height: 16),
            SelectableText(
              blob.code,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(letterSpacing: 4),
            ),
            const SizedBox(height: 8),
            Text('Fingerprint: ${blob.publicKeyFingerprint}'),
            const SizedBox(height: 4),
            Text(
              remaining.isNegative
                  ? 'Expired — reopen this to get a new code.'
                  : 'Expires in ${remaining.inMinutes}m ${remaining.inSeconds % 60}s',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: encoded));
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Pairing code copied')),
              );
            }
          },
          icon: const Icon(Icons.copy_outlined),
          label: const Text('Copy'),
        ),
        TextButton.icon(
          onPressed: () => unawaited(Share.share(encoded)),
          icon: const Icon(Icons.share_outlined),
          label: const Text('Share'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Done'),
        ),
      ],
    );
  }
}

class _PairedDeviceInput {
  const _PairedDeviceInput({
    required this.blob,
    required this.fingerprintConfirmed,
    required this.allowedCategories,
  });

  final _PairingBlob blob;
  final bool fingerprintConfirmed;
  final Set<NeuraContinuityCategory> allowedCategories;
}

class _AddDeviceDialog extends StatefulWidget {
  const _AddDeviceDialog();

  @override
  State<_AddDeviceDialog> createState() => _AddDeviceDialogState();
}

class _AddDeviceDialogState extends State<_AddDeviceDialog> {
  final _controller = TextEditingController();
  _PairingBlob? _blob;
  String? _parseError;
  bool _fingerprintConfirmed = false;
  final Set<NeuraContinuityCategory> _categories = {
    NeuraContinuityCategory.preferences,
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _parse() {
    final blob = _PairingBlob.tryParse(_controller.text);
    setState(() {
      _blob = blob;
      _parseError =
          blob == null ? 'That doesn\'t look like a valid code.' : null;
      _fingerprintConfirmed = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blob = _blob;
    return AlertDialog(
      title: const Text('Add a device'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Paste the pairing code',
                errorText: _parseError,
              ),
              onChanged: (_) => _parse(),
            ),
            if (blob != null) ...[
              const SizedBox(height: 16),
              Text(
                blob.isExpired
                    ? 'This code has expired — ask for a new one.'
                    : 'From: ${blob.displayName}',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text('Fingerprint: ${blob.publicKeyFingerprint}'),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _fingerprintConfirmed,
                onChanged: blob.isExpired
                    ? null
                    : (value) =>
                        setState(() => _fingerprintConfirmed = value ?? false),
                title: const Text(
                  'This fingerprint matches what\'s shown on the other device',
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Allow syncing for:',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Wrap(
                spacing: 8,
                children: NeuraContinuityCategory.values
                    .map(
                      (category) => FilterChip(
                        label: Text(category.name),
                        selected: _categories.contains(category),
                        onSelected: (selected) => setState(() {
                          if (selected) {
                            _categories.add(category);
                          } else {
                            _categories.remove(category);
                          }
                        }),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: blob == null ||
                  blob.isExpired ||
                  !_fingerprintConfirmed ||
                  _categories.isEmpty
              ? null
              : () => Navigator.of(context).pop(
                    _PairedDeviceInput(
                      blob: blob,
                      fingerprintConfirmed: _fingerprintConfirmed,
                      allowedCategories: _categories,
                    ),
                  ),
          child: const Text('Add device'),
        ),
      ],
    );
  }
}
