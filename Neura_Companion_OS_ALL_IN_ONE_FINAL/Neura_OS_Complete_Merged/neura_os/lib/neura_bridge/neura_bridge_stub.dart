// Web-safe stub.

class NeuraBridge {
  NeuraBridge._();

  static NeuraBridge forPlatform({String? unityExePath}) {
    throw UnsupportedError('NeuraBridge is not supported on Web in this build.');
  }

  Future<void> start() async {}

  void onEvent(void Function(Map<String, dynamic>) cb) {}

  Future<void> sendSetState({required String mood, required double energy, required String room}) async {}

  Future<void> sendAction(String action, String value) async {}
}
