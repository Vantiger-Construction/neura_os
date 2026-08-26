import 'dart:async';

import 'cloud_inference_consent.dart';
import 'compassionate_response_policy.dart';
import 'neura_safety_policy.dart';

enum NeuraModelPurpose {
  summarizeVisibleContent,
  classifyIntent,
  explainDecision,
  generateAlternatives,
  createDraft,
}

enum NeuraModelAvailabilityState {
  available,
  unavailable,
  degraded,
}

class NeuraModelAvailability {
  const NeuraModelAvailability({
    required this.state,
    this.detail = '',
  });

  final NeuraModelAvailabilityState state;
  final String detail;

  bool get isAvailable =>
      state == NeuraModelAvailabilityState.available ||
      state == NeuraModelAvailabilityState.degraded;
}

class NeuraModelRequest {
  NeuraModelRequest({
    required this.purpose,
    required this.prompt,
    required this.safetyContext,
    this.visibleContext = '',
    Iterable<String> permittedDataLabels = const <String>[],
    this.containsPrivateRecords = false,
    this.contextCapsuleId = 'personal',
    this.cloudConsentPermitId,
    this.responseGuidance,
  }) : permittedDataLabels = List<String>.unmodifiable(permittedDataLabels);

  final NeuraModelPurpose purpose;
  final String prompt;
  final String visibleContext;
  final List<String> permittedDataLabels;
  final bool containsPrivateRecords;
  final String contextCapsuleId;
  final String? cloudConsentPermitId;
  final NeuraCompassionateResponseGuidance? responseGuidance;
  final NeuraSafetyContext safetyContext;
}

class NeuraModelDelta {
  const NeuraModelDelta({
    required this.text,
    this.isFinal = false,
  });

  final String text;
  final bool isFinal;
}

class NeuraCancellationToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() {
    _cancelled = true;
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw StateError('Generation was cancelled.');
    }
  }
}

abstract class NeuraModelBackend {
  String get id;
  bool get runsLocally;

  Future<NeuraModelAvailability> checkAvailability();

  Stream<NeuraModelDelta> generate({
    required NeuraModelRequest request,
    required NeuraCancellationToken cancellation,
  });
}

typedef NeuraAvailabilityProbe = Future<NeuraModelAvailability> Function();

typedef NeuraTextGenerator = Stream<NeuraModelDelta> Function({
  required NeuraModelRequest request,
  required NeuraCancellationToken cancellation,
});

/// Adapter used to bind a native or cloud runtime without giving that runtime
/// direct access to Neura capabilities.
class NeuraCallbackModelBackend implements NeuraModelBackend {
  NeuraCallbackModelBackend({
    required this.id,
    required this.runsLocally,
    required NeuraAvailabilityProbe availabilityProbe,
    required NeuraTextGenerator generator,
  })  : _availabilityProbe = availabilityProbe,
        _generator = generator;

  @override
  final String id;

  @override
  final bool runsLocally;

  final NeuraAvailabilityProbe _availabilityProbe;
  final NeuraTextGenerator _generator;

  @override
  Future<NeuraModelAvailability> checkAvailability() {
    return _availabilityProbe();
  }

  @override
  Stream<NeuraModelDelta> generate({
    required NeuraModelRequest request,
    required NeuraCancellationToken cancellation,
  }) {
    return _generator(
      request: request,
      cancellation: cancellation,
    );
  }
}

class NeuraFoundryLocalBackend extends NeuraCallbackModelBackend {
  NeuraFoundryLocalBackend({
    required super.availabilityProbe,
    required super.generator,
  }) : super(
          id: 'foundry_local_windows',
          runsLocally: true,
        );
}

class NeuraAndroidOnDeviceBackend extends NeuraCallbackModelBackend {
  NeuraAndroidOnDeviceBackend({
    required super.availabilityProbe,
    required super.generator,
  }) : super(
          id: 'android_on_device',
          runsLocally: true,
        );
}

class NeuraOnnxLocalBackend extends NeuraCallbackModelBackend {
  NeuraOnnxLocalBackend({
    required super.availabilityProbe,
    required super.generator,
  }) : super(
          id: 'onnx_local',
          runsLocally: true,
        );
}

class NeuraCloudModelBackend extends NeuraCallbackModelBackend {
  NeuraCloudModelBackend({
    required super.id,
    required super.availabilityProbe,
    required super.generator,
  }) : super(runsLocally: false);
}

/// Local-first model router.
///
/// Model output is text-only and never carries execution authority. Any action
/// derived from output must be independently registered, reviewed, and
/// submitted through Action Loom.
class NeuraLocalModelRouter {
  NeuraLocalModelRouter({
    required this.safetyPolicy,
    Iterable<NeuraModelBackend> backends = const <NeuraModelBackend>[],
    NeuraCloudInferenceConsentRegistry? cloudConsentRegistry,
    this.enabled = false,
  })  : _backends = List<NeuraModelBackend>.unmodifiable(backends),
        cloudConsentRegistry = cloudConsentRegistry ??
            NeuraCloudInferenceConsentRegistry(
              safetyPolicy: safetyPolicy,
            );

  final NeuraLivingSafetyPolicy safetyPolicy;
  final NeuraCloudInferenceConsentRegistry cloudConsentRegistry;
  final List<NeuraModelBackend> _backends;
  bool enabled;

  List<NeuraModelBackend> get backends => _backends;

  Stream<NeuraModelDelta> generate(
    NeuraModelRequest request, {
    required NeuraCancellationToken cancellation,
  }) async* {
    if (!enabled) {
      throw StateError('Private Neural Core is disabled.');
    }

    _requireInferenceAllowed(request);
    cancellation.throwIfCancelled();

    final local = await _firstAvailable(
      _backends.where((backend) => backend.runsLocally),
    );

    NeuraModelBackend? selected = local;
    if (selected == null &&
        safetyPolicy.canUseCloudInference(request.safetyContext) &&
        !request.containsPrivateRecords) {
      final consent = _validateCloudConsent(request);
      if (!consent.allowed) {
        throw StateError(consent.reason);
      }

      final cloud = await _firstAvailable(
        _backends.where((backend) => !backend.runsLocally),
      );
      if (cloud != null) {
        final consumed = _consumeCloudConsent(request);
        if (!consumed.allowed) {
          throw StateError(consumed.reason);
        }
        selected = cloud;
      }
    }

    if (selected == null) {
      throw StateError(
        'No permitted model backend is currently available.',
      );
    }

    await for (final delta in selected.generate(
      request: request,
      cancellation: cancellation,
    )) {
      cancellation.throwIfCancelled();
      _requireInferenceAllowed(request);
      yield delta;
    }
  }

  void _requireInferenceAllowed(NeuraModelRequest request) {
    if (safetyPolicy.safeModeActive || request.safetyContext.recoveryMode) {
      throw StateError(
        'Model inference is blocked by Safe Mode or Recovery mode.',
      );
    }
  }

  NeuraCloudInferenceConsentDecision _validateCloudConsent(
    NeuraModelRequest request,
  ) {
    return cloudConsentRegistry.validate(
      permitId: request.cloudConsentPermitId,
      purposeId: request.purpose.name,
      contextCapsuleId: request.contextCapsuleId,
      requestedDataLabels: request.permittedDataLabels,
      containsPrivateRecords: request.containsPrivateRecords,
      context: request.safetyContext,
    );
  }

  NeuraCloudInferenceConsentDecision _consumeCloudConsent(
    NeuraModelRequest request,
  ) {
    return cloudConsentRegistry.validateAndConsume(
      permitId: request.cloudConsentPermitId,
      purposeId: request.purpose.name,
      contextCapsuleId: request.contextCapsuleId,
      requestedDataLabels: request.permittedDataLabels,
      containsPrivateRecords: request.containsPrivateRecords,
      context: request.safetyContext,
    );
  }

  Future<NeuraModelBackend?> _firstAvailable(
    Iterable<NeuraModelBackend> candidates,
  ) async {
    for (final backend in candidates) {
      final availability = await backend.checkAvailability();
      if (availability.isAvailable) {
        return backend;
      }
    }
    return null;
  }
}
