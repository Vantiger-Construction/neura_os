import 'dart:io';
import 'package:flutter_test/flutter_test.dart' show Fake;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

/// Registers a [PathProviderPlatform] that returns [Directory.systemTemp]
/// for all path queries. Call [registerMockPathProvider] in setUpAll.
void registerMockPathProvider({String? rootPath}) {
  PathProviderPlatform.instance = _MockPathProvider(rootPath);
}

class _MockPathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _MockPathProvider(String? rootPath)
      : _tmp = rootPath ?? Directory.systemTemp.path;

  final String _tmp;

  @override
  Future<String?> getTemporaryPath() async => _tmp;

  @override
  Future<String?> getApplicationDocumentsPath() async => _tmp;

  @override
  Future<String?> getApplicationSupportPath() async => _tmp;

  @override
  Future<String?> getApplicationCachePath() async => _tmp;

  @override
  Future<String?> getExternalStoragePath() async => _tmp;

  @override
  Future<List<String>?> getExternalCachePaths() async => [_tmp];

  @override
  Future<List<String>?> getExternalStoragePaths({
    StorageDirectory? type,
  }) async =>
      [_tmp];

  @override
  Future<String?> getDownloadsPath() async => _tmp;

  @override
  Future<String?> getLibraryPath() async => _tmp;
}
