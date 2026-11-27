/// A shared recording contract; implementations declare their own data path.
abstract interface class NeuraSpeechInput {
  Stream<String> get transcriptStream;
  Stream<String> get finalPhraseStream;
  Stream<String> get statusStream;
  bool get isListening;
  Future<bool> startRecording();
  Future<String> stopRecording();
}

/// Implemented by recognizers that know which language they heard, either
/// because the model identified it or because it was asked to listen for it.
abstract interface class NeuraSpeechLanguageSource {
  /// Two-letter code of the most recent turn's language, or null if unknown.
  String? get heardLanguage;
}
