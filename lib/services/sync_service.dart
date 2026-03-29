import 'package:connectivity_plus/connectivity_plus.dart';

class SyncService {
  /// Starts sync process when connectivity is available.
  Future<void> syncAll() async {
    final statuses = await Connectivity().checkConnectivity();
    if (statuses.every((s) => s == ConnectivityResult.none)) return;
    // TODO: pull remote changes, push local changes, resolve conflicts
  }
}
