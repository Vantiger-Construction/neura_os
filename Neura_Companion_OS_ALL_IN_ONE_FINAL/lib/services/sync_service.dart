import 'package:connectivity_plus/connectivity_plus.dart';

class SyncService {
  /// Starts sync process when connectivity is available.
  Future<void> syncAll() async {
    final conn = await Connectivity().checkConnectivity();
    if (conn == ConnectivityResult.none) return;
    // TODO: pull remote changes, push local changes, resolve conflicts
  }
}
