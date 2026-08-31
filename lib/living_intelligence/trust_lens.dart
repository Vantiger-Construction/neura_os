import '../intelligence/models.dart';

class NeuraDecisionReceiptV2 {
  NeuraDecisionReceiptV2({
    required this.capabilityId,
    required this.intentSummary,
    required Iterable<String> evidenceLabels,
    required Iterable<String> excludedSources,
    required Iterable<String> alternatives,
    required double confidence,
    required this.reversible,
    required this.approvalMode,
    this.undoDescription,
  })  : evidenceLabels = List<String>.unmodifiable(evidenceLabels),
        excludedSources = List<String>.unmodifiable(excludedSources),
        alternatives = List<String>.unmodifiable(alternatives),
        confidence = confidence.clamp(0.0, 1.0).toDouble();

  final String capabilityId;
  final String intentSummary;
  final List<String> evidenceLabels;
  final List<String> excludedSources;
  final List<String> alternatives;
  final double confidence;
  final bool reversible;
  final String? undoDescription;
  final NeuraApprovalMode approvalMode;

  bool get grantsExecutionAuthority => false;

  Map<String, Object?> toJson() {
    return {
      'v': 2,
      'capability_id': capabilityId,
      'intent_summary': intentSummary,
      'evidence_labels': evidenceLabels,
      'excluded_sources': excludedSources,
      'alternatives': alternatives,
      'confidence': confidence,
      'reversible': reversible,
      'undo_description': undoDescription,
      'approval_mode': approvalMode.name,
      'grants_execution_authority': false,
    };
  }
}

/// Builds bounded, derived decision receipts without raw personal copy.
class NeuraTrustLens {
  const NeuraTrustLens();

  NeuraDecisionReceiptV2 build({
    required String capabilityId,
    required String intentSummary,
    required Iterable<String> evidenceLabels,
    required Iterable<String> excludedSources,
    required Iterable<String> alternatives,
    required double confidence,
    required bool reversible,
    required NeuraApprovalMode approvalMode,
    String? undoDescription,
  }) {
    return NeuraDecisionReceiptV2(
      capabilityId: _bounded(capabilityId, 80),
      intentSummary: _bounded(intentSummary, 160),
      evidenceLabels: evidenceLabels.map(_safeEvidenceLabel),
      excludedSources: excludedSources.map(_safeSourceId),
      alternatives: alternatives.map(
        (value) => _bounded(value, 120),
      ),
      confidence: confidence,
      reversible: reversible,
      approvalMode: approvalMode,
      undoDescription:
          undoDescription == null ? null : _bounded(undoDescription, 120),
    );
  }

  String _safeEvidenceLabel(String value) {
    final normalized = _bounded(value, 120);
    final lower = normalized.toLowerCase();

    for (final marker in _rawContentMarkers) {
      if (lower.contains(marker)) {
        throw ArgumentError.value(
          value,
          'evidenceLabels',
          'Raw personal content is not allowed in a Trust Lens receipt.',
        );
      }
    }
    return normalized;
  }

  String _safeSourceId(String value) {
    final normalized = _bounded(value, 64).toLowerCase();
    if (!RegExp(r'^[a-z0-9_ -]+$').hasMatch(normalized)) {
      throw ArgumentError.value(
        value,
        'excludedSources',
        'Source identifiers must be labels, not raw content.',
      );
    }
    return normalized.replaceAll(' ', '_');
  }

  String _bounded(String value, int maxLength) {
    final normalized = value
        .trim()
        .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ');

    if (normalized.isEmpty) {
      throw ArgumentError.value(value, 'value', 'A non-empty label is needed.');
    }

    if (normalized.length <= maxLength) {
      return normalized;
    }
    return normalized.substring(0, maxLength);
  }

  static const _rawContentMarkers = <String>[
    'journal:',
    'therapy:',
    'message:',
    'mood note:',
    'prompt:',
    'raw:',
    'conversation:',
  ];
}
