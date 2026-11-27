import 'dart:io';

/// Mirrors the native runtime gate (`NEURA_ON_DEVICE_ASR_ENABLE` exactly `1`)
/// so chat does not query the streaming engine at all unless the person
/// opted in. The native side still makes the authoritative check.
bool neuraOnDeviceAsrOptedIn() =>
    Platform.environment['NEURA_ON_DEVICE_ASR_ENABLE'] == '1';
