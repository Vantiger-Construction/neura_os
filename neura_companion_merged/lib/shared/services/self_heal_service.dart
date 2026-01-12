class SelfHealService {
  SelfHealService._internal();
  static final SelfHealService instance = SelfHealService._internal();

  Future<void> recordError(String where, Object error, StackTrace st) async {
    // TODO: plug into your real diagnostics / logging system.
    // For now this is a no-op stub.
  }
}
