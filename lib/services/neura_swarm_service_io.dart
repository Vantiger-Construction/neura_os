import 'dart:async';
import 'dart:io';

import '../reliability/safe_boot.dart';
import '../rust_bridge/api.dart' as rust_api;
import '../rust_bridge/frb_generated.dart';

/// Native wrapper around the `neura_swarm` Rust crate.
class NeuraSwarmService {
  NeuraSwarmService._();
  static final NeuraSwarmService instance = NeuraSwarmService._();

  bool _initialized = false;
  bool _clearingCredential = false;
  bool _credentialBlocked = false;
  bool _credentialSuspended = false;
  int _credentialGeneration = 0;
  Future<void> _credentialQueue = Future<void>.value();
  final Set<Future<SwarmOutcome>> _activeReviews =
      <Future<SwarmOutcome>>{};

  Future<void> init(String apiKey) {
    if (SafeBoot.instance.safeMode.value ||
        _credentialSuspended ||
        _clearingCredential) {
      return Future<void>.error(
        StateError(
          'The native Neura swarm is unavailable while Safe Mode is active.',
        ),
      );
    }
    if (!Platform.isWindows) {
      return Future<void>.error(
        UnsupportedError(
          'The packaged native Neura swarm is currently available on Windows only.',
        ),
      );
    }
    return _enqueueCredentialMutation(() async {
      if (SafeBoot.instance.safeMode.value ||
          _credentialSuspended ||
          _clearingCredential) {
        throw StateError(
          'Native provider credential initialization was blocked.',
        );
      }
      if (!_initialized) {
        await RustLib.init();
        _initialized = true;
      }
      if (SafeBoot.instance.safeMode.value ||
          _credentialSuspended ||
          _clearingCredential) {
        // Rust may now be loaded, but the credential must never cross the FFI
        // boundary after a concurrent wipe or Safe Mode transition.
        return;
      }
      await rust_api.init(apiKey: apiKey);
      if (SafeBoot.instance.safeMode.value ||
          _credentialSuspended ||
          _clearingCredential) {
        await rust_api.init(apiKey: '');
        throw StateError(
          'Native provider credential initialization was revoked.',
        );
      }
      _credentialBlocked = false;
    });
  }

  Future<void> clearCredential() => _clearCredential(permanent: false);

  /// Full-wipe variant that rejects every later native credential write in
  /// this process. A restart is the only resume boundary.
  Future<void> clearCredentialForDataWipe() =>
      _clearCredential(permanent: true);

  Future<void> _clearCredential({required bool permanent}) async {
    if (permanent) _credentialSuspended = true;
    if (!Platform.isWindows) {
      _credentialBlocked = true;
      return;
    }
    _clearingCredential = true;
    _credentialBlocked = true;
    _credentialGeneration += 1;
    try {
      await _enqueueCredentialMutation(_clearCredentialNow);
    } finally {
      _clearingCredential = false;
    }
  }

  Future<void> _clearCredentialNow() async {
    // The mutation queue drains any native init already in progress before
    // this check, preventing a late initialization from surviving a no-op.
    if (!_initialized) return;
    var globalClearFailed = false;
    var reviewDrainTimedOut = false;
    // Clear the process-global copy first. Even if an already-running review
    // takes too long to drain, no new review can acquire the old key.
    try {
      await rust_api.init(apiKey: '');
    } catch (_) {
      globalClearFailed = true;
    }

    // Each Rust review holds a short-lived zeroizing clone of the key.
    // Give those calls a short grace period, but never let an unreachable
    // network endpoint hang a privacy wipe indefinitely. Rust's own HTTP
    // timeout bounds the residual clone, whose Drop implementation wipes it.
    final activeReviews = List<Future<SwarmOutcome>>.from(_activeReviews);
    if (activeReviews.isNotEmpty) {
      try {
        await Future.wait<void>(
          activeReviews.map((review) async {
            try {
              await review;
            } catch (_) {
              // Review failures do not prevent the global clear above.
            }
          }),
        ).timeout(const Duration(seconds: 3));
      } on TimeoutException {
        reviewDrainTimedOut = true;
      }
    }
    if (globalClearFailed || reviewDrainTimedOut) {
      throw StateError(
        globalClearFailed
            ? 'The native provider credential could not be cleared.'
            : 'A native review is still releasing its provider credential.',
      );
    }
  }

  Future<void> _enqueueCredentialMutation(
    Future<void> Function() operation,
  ) {
    final next = _credentialQueue.then(
      (_) => operation(),
      onError: (_) => operation(),
    );
    _credentialQueue = next.then<void>((_) {}, onError: (_) {});
    return next;
  }

  Future<SwarmOutcome> reviewAndExtract({
    required String transcript,
    required String draftReply,
    required String userMessage,
  }) async {
    if (SafeBoot.instance.safeMode.value ||
        !Platform.isWindows ||
        !_initialized ||
        _clearingCredential ||
        _credentialBlocked ||
        _credentialSuspended) {
      return const SwarmOutcome(concernNote: null, facts: []);
    }
    final generation = _credentialGeneration;
    late final Future<SwarmOutcome> review;
    review = rust_api
        .reviewAndExtract(
          transcript: transcript,
          draftReply: draftReply,
          userMessage: userMessage,
        )
        .then(
          (raw) => generation == _credentialGeneration
              ? SwarmOutcome._fromRust(raw)
              : const SwarmOutcome(concernNote: null, facts: []),
        );
    _activeReviews.add(review);
    try {
      return await review;
    } finally {
      _activeReviews.remove(review);
    }
  }
}

class SwarmOutcome {
  final String? concernNote;
  final List<SwarmFact> facts;

  const SwarmOutcome({required this.concernNote, required this.facts});

  factory SwarmOutcome._fromRust(rust_api.SwarmOutcome raw) {
    final verdict = raw.verdict;
    final note = verdict is rust_api.SwarmVerdict_Concern ? verdict.note : null;
    return SwarmOutcome(
      concernNote: note,
      facts: raw.facts
          .map((fact) => SwarmFact(summary: fact.summary, kind: fact.kind))
          .toList(),
    );
  }
}

class SwarmFact {
  final String summary;
  final String kind;

  const SwarmFact({required this.summary, required this.kind});
}
