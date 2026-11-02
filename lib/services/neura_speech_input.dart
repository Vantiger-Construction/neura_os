/// A shared recording contract; implementations declare their own data path.
abstract interface class NeuraSpeechInput {
  Stream<String> get transcriptStream;
  Stream<String> get finalPhraseStream;
  Stream<String> get statusStream;
  bool get isListening;
  Future<bool> startRecording();
  Future<String> stopRecording();
}
