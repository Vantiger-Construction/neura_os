import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/startup/neura_bootstrap_log.dart';
import 'package:neuro_companion/startup/neura_prefs_cache.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

/// Every filesystem operation in a wipe scenario is confined to this fresh
/// fixture. Environment-based bootstrap paths are redirected before use.
/// No real secure storage, preferences, microphone or network is available.
class DataWipeFixture {
  static bool _preferencesInitialized = false;
  static const secureChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  static const memoryKey = 'neura.memoryGraph.seed.v2';
  static const providerKey = 'neura.anthropic_api_key.v1';
  static const modelKey = 'neura.openai_api_key.v1';
  static const backupKey = 'neura.scheduled_backup.passphrase.v1';
  static const tombstoneKey =
      'neura.anthropic_api_key.legacy_migration_disabled.v1';

  DataWipeFixture._(this.root, this.originalBootstrapPath)
      : originalBootstrapParent = File(originalBootstrapPath).parent.path;

  final Directory root;
  final String originalBootstrapPath;
  final String originalBootstrapParent;
  final preferences = WipePreferencesStore();
  final secrets = <String, String>{};
  final ignoredSecretDeletes = <String>{};
  final thrownSecretDeletes = <String>{};
  final deletedSecretKeys = <String>[];
  final blockedPaths = <String>[];
  final escapedPaths = <String>[];
  final platformCalls = <MethodCall>[];
  String? failedDocumentsLookup;
  String? failedTemporaryLookup;
  int networkAttempts = 0;
  PausedWipeFile? pausedFile;
  Future<void> Function(String key)? beforeSecretDelete;

  Directory get documents => Directory('${root.path}/documents');
  Directory get support => Directory('${root.path}/support');
  Directory get temporary => Directory('${root.path}/plugin-temp');
  Directory get systemTemporary => Directory('${root.path}/system-temp');
  String get bootstrapPath => '${root.path}/bootstrap/bootstrap_crash.ndjson';

  static Future<DataWipeFixture> create() async {
    final root = await Directory.systemTemp.createTemp('neura-full-wipe-test-');
    final fixture = DataWipeFixture._(root, NeuraBootstrapLog.location);
    for (final directory in [
      fixture.documents,
      fixture.support,
      fixture.temporary,
      fixture.systemTemporary,
      Directory('${root.path}/bootstrap'),
    ]) {
      await directory.create(recursive: true);
    }
    final originalPaths = PathProviderPlatform.instance;
    final originalPreferences = SharedPreferencesStorePlatform.instance;
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      SharedPreferencesStorePlatform.instance = originalPreferences;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(secureChannel, null);
      for (final channel in _forbiddenChannels) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), null);
      }
      if (await root.exists()) await root.delete(recursive: true);
    });
    PathProviderPlatform.instance = _WipePathProvider(fixture);
    // Set the SDK's singleton to a mock before replacing its store. The
    // fixture then models durable platform state separately from its cache.
    if (!_preferencesInitialized) {
      SharedPreferences.setMockInitialValues({});
      _preferencesInitialized = true;
    }
    SharedPreferencesStorePlatform.instance = fixture.preferences;
    await NeuraPrefsCache.init();
    await NeuraPrefsCache.prefs.reload();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(secureChannel, (call) async {
      final args = call.arguments as Map;
      final key = args['key'] as String;
      switch (call.method) {
        case 'read':
          return fixture.secrets[key];
        case 'write':
          fixture.secrets[key] = args['value'] as String;
          return null;
        case 'delete':
          fixture.deletedSecretKeys.add(key);
          await fixture.beforeSecretDelete?.call(key);
          if (fixture.thrownSecretDeletes.contains(key)) {
            throw PlatformException(code: 'synthetic-delete-failure');
          }
          if (!fixture.ignoredSecretDeletes.contains(key)) {
            fixture.secrets.remove(key);
          }
          return null;
      }
      throw StateError('Unexpected secure operation: ${call.method}');
    });
    for (final channel in _forbiddenChannels) {
      messenger.setMockMethodCallHandler(MethodChannel(channel), (call) async {
        fixture.platformCalls.add(call);
        throw StateError('Native capture or speech is forbidden in this test.');
      });
    }
    return fixture;
  }

  static const _forbiddenChannels = [
    'com.llfbandit.record/messages',
    'plugin.csdcorp.com/speech_to_text',
    'neura/speech_to_text',
    'flutter_tts',
  ];

  Future<T> run<T>(Future<T> Function() body) {
    final outer = Zone.current;
    return HttpOverrides.runZoned(
      () => IOOverrides.runZoned(
        body,
        getSystemTempDirectory: () => systemTemporary,
        createDirectory: (path) => outer.run(() => Directory(_guard(path))),
        createFile: (path) {
          final guarded = _guard(path);
          final paused = pausedFile;
          if (paused != null && guarded == paused.path) return paused;
          return outer.run(() => File(guarded));
        },
        createLink: (path) => outer.run(() => Link(_guard(path))),
        fseGetType: (path, followLinks) async {
          final guarded = _guard(path);
          if (blockedPaths.contains(guarded)) {
            throw FileSystemException('Synthetic private path failure.', path);
          }
          return outer.run(
            () => FileSystemEntity.type(guarded, followLinks: followLinks),
          );
        },
      ),
      createHttpClient: (_) {
        networkAttempts += 1;
        throw StateError('Network access is forbidden in wipe tests.');
      },
    );
  }

  String _guard(String path) {
    if (path == originalBootstrapParent) return '${root.path}/bootstrap';
    if (path == originalBootstrapPath) return bootstrapPath;
    if (path == '$originalBootstrapPath.old') return '$bootstrapPath.old';
    if (path == root.path ||
        path.startsWith('${root.path}${Platform.pathSeparator}')) {
      return path;
    }
    escapedPaths.add(path);
    throw StateError('Filesystem operation escaped synthetic storage.');
  }

  Future<File> seed(String path,
      [String content = 'synthetic private fixture']) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString(content);
  }

  void expectIsolation() {
    expect(escapedPaths, isEmpty);
    expect(platformCalls, isEmpty);
    expect(networkAttempts, 0);
  }
}

class WipePreferencesStore extends SharedPreferencesStorePlatform {
  final data = <String, Object>{};
  bool refuseClear = false;
  bool throwOnClear = false;
  bool ignoreClear = false;

  @override
  bool get isMock => true;

  @override
  Future<bool> clear() async {
    if (throwOnClear) throw StateError('Synthetic preference cleanup failure.');
    if (refuseClear) return false;
    if (!ignoreClear) data.clear();
    return true;
  }

  @override
  Future<Map<String, Object>> getAll() async => Map.from(data);

  @override
  Future<bool> remove(String key) async {
    data.remove(key);
    return true;
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    return true;
  }
}

class _WipePathProvider extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _WipePathProvider(this.fixture);
  final DataWipeFixture fixture;

  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (fixture.failedDocumentsLookup != null) {
      throw StateError(fixture.failedDocumentsLookup!);
    }
    return fixture.documents.path;
  }

  @override
  Future<String?> getApplicationSupportPath() async => fixture.support.path;

  @override
  Future<String?> getTemporaryPath() async {
    if (fixture.failedTemporaryLookup != null) {
      throw StateError(fixture.failedTemporaryLookup!);
    }
    return fixture.temporary.path;
  }
}

/// Holds a real synthetic graph append past the drain deadline. Release can
/// recreate the parent to model an OS write completing after directory removal.
class PausedWipeFile extends Fake implements File {
  PausedWipeFile(this.delegate);
  final File delegate;
  final started = Completer<void>();
  final release = Completer<void>();

  @override
  String get path => delegate.path;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    started.complete();
    await release.future;
    await delegate.parent.create(recursive: true);
    return delegate.writeAsString(contents,
        mode: mode, encoding: encoding, flush: flush);
  }
}
