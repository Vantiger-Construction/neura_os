import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../adaptive_intent/neura_adaptive_intent_runtime.dart';
import '../../core/memory/memory_crypto.dart';
import '../../core/memory/memory_consolidation_service.dart';
import '../../core/memory/memory_graph_service.dart';
import '../../core/neura_error_vault.dart';
import '../../care/services/care_mode_bridge.dart';
import '../../care/services/contact_share_service.dart';
import '../../constitution/neura_constitution_service.dart';
import '../../services/scheduled_backup_settings.dart';
import '../../services/sync_conflict_log.dart';
import '../../care/services/trusted_contacts_service.dart';
import '../../dashboard/proactive_banner_service.dart';
import '../../dreams/services/dream_theme_service.dart';
import '../../intelligence/action_loom.dart';
import '../../intelligence/neura_intelligence_controller.dart';
import '../../insights/services/weekly_summarist_service.dart';
import '../../memory/space_memory_engine.dart';
import '../../mascot/neura_window_role.dart';
import '../../neura_runtime/neura_runtime_controller.dart';
import '../../modules/coach/coach_store.dart';
import '../../modules/core/app_log.dart';
import '../../modules/vault/memory_vault_store.dart';
import '../../modules/vault/vault_session.dart';
import '../../modules/human/human_prefs_controller.dart';
import '../../modules/humor/joke_prefs_controller.dart';
import '../../modules/money/money_store.dart';
import '../../modules/mood/mood_store.dart';
import '../../modules/pay_it_forward/goodwill_controller.dart';
import '../../modules/therapy/therapy_response_store.dart';
import '../../notifications/neura_notifications_prefs.dart';
import '../../notifications/neura_notifications_service.dart';
import '../../persona/services/agent_selection_service.dart';
import '../../persona/services/neura_audience_service.dart';
import '../../persona/services/neura_persona_service.dart';
import '../../reliability/module_health_monitor.dart';
import '../../reliability/safe_boot.dart';
import '../../reliability/timeline_vault.dart';
import '../../relationships/services/feedback_service.dart';
import '../../relationships/services/interaction_service.dart';
import '../../relationships/services/promise_service.dart';
import '../../relationships/services/relationship_profile_service.dart';
import '../../shared/services/self_heal_service.dart';
import '../../services/ambient_listening_prefs.dart';
import '../../services/ambient_listening_service.dart';
import '../../services/app_lock_prefs.dart';
import '../../services/auth_service.dart';
import '../../services/avatar_service.dart';
import '../../services/neura_model_credentials.dart';
import '../../services/neura_provider_credentials.dart';
import '../../services/neura_ai_service.dart';
import '../../services/neura_llm_diagnostics.dart';
import '../../services/sleep_listener_service.dart';
import '../../services/neura_swarm_service.dart';
import '../../services/neura_tone_runtime.dart';
import '../../services/wake_word_listener_service.dart';
import '../../services/wake_word_prefs.dart';
import '../../startup/neura_bootstrap_log.dart';
import '../../mood/services/mood_state_service.dart';
import '../modules/focus/focus_controller.dart';

/// Raised only after every known deletion has been attempted.
///
/// The labels intentionally omit paths and underlying platform messages so a
/// privacy error cannot accidentally reveal user data in the UI.
class NeuraDataWipeException implements Exception {
  const NeuraDataWipeException(this.failedSteps);

  final List<String> failedSteps;

  @override
  String toString() =>
      'Local data removal is incomplete. Failed: ${failedSteps.join(', ')}.';
}

class NeuraDataWipeService {
  static const _documentDirectoryNames = <String>[
    'neura_memory',
    'neura_therapy',
    'neura_ambient_audio',
    'neura_legacy_vault',
  ];

  static final RegExp _sleepRecordingName = RegExp(r'^sleep_[0-9]+\.m4a$');

  // Every temporary artifact currently produced by Neura. Matching is
  // anchored and only direct children of a platform-provided temp root are
  // considered, so unrelated temp files can never be removed.
  static final List<RegExp> _temporaryArtifactNames = <RegExp>[
    RegExp(r'^neura_error_vault\.jsonl(?:\.[1-3])?$'),
    RegExp(r'^neura_bootstrap_export_[0-9TZ.-]+\.ndjson$'),
    RegExp(r'^usage_entries_[0-9]+\.csv$'),
    RegExp(r'^usage_report_[0-9]+\.pdf$'),
    RegExp(r'^neura_weekly_snapshot_[0-9]+\.(?:csv|pdf)$'),
    RegExp(r'^neura_recap_[0-9]+\.pdf$'),
    RegExp(r'^neura_legacy_vault_export_[0-9]+\.zip$'),
    RegExp(r'^legacy_packet_.+_[0-9]+\.zip$'),
    RegExp(r'^legacy_.+_[0-9]+\.pdf$'),
    RegExp(r'^neura_life_timeline_.+\.json$'),
    RegExp(r'^amb_playback_[0-9]+\.wav$'),
  ];

  /// Deletes all app-owned local state currently written by Neura.
  ///
  /// Active microphone producers and queued writers are stopped first. Every
  /// secret store and file target is then attempted even if another step
  /// fails; any unverified deletion is reported at the end instead of being
  /// hidden behind a false success message.
  static Future<void> wipeAllLocalData() async {
    final failures = <String>[];

    // Disable opt-in producers synchronously before awaiting their shutdown.
    // Keep the live gate closed for the rest of this process; the next launch
    // starts clean after the persisted Safe Boot marker is deleted.
    SafeBoot.instance.safeMode.value = true;
    NeuraAiService.instance.cancelActiveGeneration();
    AmbientListeningPrefsController.instance.resetAfterDataWipe();
    WakeWordPrefsController.instance.resetAfterDataWipe();
    await _attempt(
      failures,
      'native crash-log writer shutdown',
      NeuraWindowRole.suspendDiagnosticsForDataWipe,
    );
    await _attempt(
      failures,
      'error-vault writer shutdown',
      NeuraErrorVault.suspendForDataWipe,
    );
    await _attempt(
      failures,
      'bootstrap-log writer shutdown',
      NeuraBootstrapLog.suspendForDataWipe,
    );
    await _attempt(
      failures,
      'ambient microphone shutdown',
      AmbientListeningService.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'wake-word microphone shutdown',
      WakeWordListenerService.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'sleep recording shutdown',
      SleepListenerService.resetAllAfterDataWipe,
    );
    await _attempt(
      failures,
      'scheduled notification removal',
      NeuraNotificationsService.instance.cancelAllForDataWipe,
    );
    await _attempt(
      failures,
      'room-memory runtime shutdown',
      NeuraRuntimeController.I.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'memory consolidation drain',
      MemoryConsolidationService.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'weekly summary drain',
      WeeklySummaristService.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'memory graph writer shutdown',
      MemoryGraphService.I.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'mood history writer shutdown',
      MoodStore.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'money history writer shutdown',
      MoneyStore.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'therapy journal writer shutdown',
      TherapyResponseStore.I.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'care history cache reset',
      CareModeBridge.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'relationship interaction cache reset',
      InteractionService.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'relationship feedback cache reset',
      FeedbackService.instance.resetAfterDataWipe,
    );

    // Drain persistent writers and release cached file paths before removing
    // their parent directories.
    await _attempt(
      failures,
      'adaptive intent shutdown',
      NeuraAdaptiveIntentRuntime.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'proactive banner cache reset',
      ProactiveBannerService.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'action approval cache reset',
      NeuraActionLoom.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'intelligence cache reset',
      NeuraIntelligenceController.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'timeline cache reset',
      TimelineVault.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'log cache reset',
      AppLog.instance.resetAfterDataWipe,
    );
    await _attempt(
      failures,
      'safe-boot cache reset',
      SafeBoot.instance.resetAfterDataWipe,
    );

    // Forget sensitive in-memory objects before clearing their backing prefs.
    // This closes the window where a live controller could write an old cache
    // back after SharedPreferences.clear() but before its own reset.
    FocusController.instance.resetAfterDataWipe();
    HumanPrefsController.instance.resetAfterDataWipe();
    AppLockPrefsController.instance.resetAfterDataWipe();
    JokePrefsController.instance.resetAfterDataWipe();
    NeuraNotificationsPrefsController.instance.resetAfterDataWipe();
    TrustedContactsService.instance.resetAfterDataWipe();
    ContactShareService.instance.resetAfterDataWipe();
    SyncConflictLog.instance.resetAfterDataWipe();
    DreamThemeService.instance.resetAfterDataWipe();
    RelationshipProfileService.instance.resetAfterDataWipe();
    PromiseService.instance.resetAfterDataWipe();
    NeuraPersonaService.instance.resetAfterDataWipe();
    NeuraAudienceService.instance.resetAfterDataWipe();
    AgentSelectionService.instance.resetAfterDataWipe();
    MoodStateService.instance.resetAfterDataWipe();
    NeuraConstitutionService.instance.resetAfterDataWipe();
    GoodwillController.instance.resetAfterDataWipe();
    SpaceMemoryEngine.instance.resetAfterDataWipe();
    VaultSession.lock();
    AvatarService.instance.resetAfterDataWipe();
    NeuraToneRuntime.instance.resetAfterDataWipe();
    CoachStore.instance.resetAfterDataWipe();
    ModuleHealthMonitor.instance.resetAfterDataWipe();
    NeuraLlmDiagnostics.instance.resetAfterDataWipe();
    SelfHealService.instance.clearLog();

    await _attempt(
      failures,
      'memory vault deletion',
      MemoryVaultStore.instance.wipe,
    );
    // These operations remove or invalidate live secrets. They are
    // independently attempted and any failure is always surfaced.
    await _attempt(
      failures,
      'native provider credential deletion',
      NeuraSwarmService.instance.clearCredentialForDataWipe,
    );
    await _attempt(
      failures,
      'device encryption key deletion',
      MemoryCrypto.clearDeviceKey,
    );
    await _attempt(
      failures,
      'provider credential deletion',
      NeuraProviderCredentials.instance.clearForDataWipe,
    );
    await _attempt(
      failures,
      'model credential deletion',
      NeuraModelCredentials.instance.clearForDataWipe,
    );
    await _attempt(
      failures,
      'scheduled backup settings deletion',
      ScheduledBackupSettings.instance.clearForDataWipe,
    );
    await _attempt(
      failures,
      'local sign-in session removal',
      AuthService().clearLocalSessionForDataWipe,
    );

    await _attempt(failures, 'preferences deletion', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();
      if (prefs.getKeys().isNotEmpty) {
        throw StateError('SharedPreferences deletion could not be verified.');
      }
    });

    await _wipeApplicationDocuments(failures);
    await _wipeApplicationSupport(failures);
    await _wipeTemporaryArtifacts(failures);

    if (failures.isNotEmpty) {
      throw NeuraDataWipeException(List<String>.unmodifiable(failures));
    }
    MemoryCrypto.resumeAfterDataWipe();
    NeuraAdaptiveIntentRuntime.instance.resumeAfterDataWipe();
    ProactiveBannerService.instance.resumeAfterDataWipe();
    NeuraActionLoom.instance.resumeAfterDataWipe();
    NeuraIntelligenceController.instance.resumeAfterDataWipe();
  }

  /// Deletes only the exact Legacy Vault directory in application documents.
  static Future<void> wipeLegacyVault() async {
    final failures = <String>[];
    await _withDirectory(
      failures,
      'application documents lookup',
      getApplicationDocumentsDirectory,
      (documents) => _deleteExact(
        failures,
        '${documents.path}${Platform.pathSeparator}neura_legacy_vault',
        'Legacy Vault deletion',
      ),
    );
    if (failures.isNotEmpty) {
      throw NeuraDataWipeException(List<String>.unmodifiable(failures));
    }
  }

  static Future<void> _wipeApplicationDocuments(List<String> failures) {
    return _withDirectory(
      failures,
      'application documents lookup',
      getApplicationDocumentsDirectory,
      (documents) async {
        for (final name in _documentDirectoryNames) {
          await _deleteExact(
            failures,
            '${documents.path}${Platform.pathSeparator}$name',
            '$name deletion',
          );
        }
        await _deleteMatchingChildren(
          failures,
          documents,
          (name) => _sleepRecordingName.hasMatch(name),
          'sleep recording deletion',
        );
      },
    );
  }

  static Future<void> _wipeApplicationSupport(List<String> failures) {
    return _withDirectory(
      failures,
      'application support lookup',
      getApplicationSupportDirectory,
      (support) => _deleteExact(
        failures,
        '${support.path}${Platform.pathSeparator}neura',
        'Neura app-support deletion',
      ),
    );
  }

  static Future<void> _wipeTemporaryArtifacts(List<String> failures) async {
    final roots = <String>{Directory.systemTemp.path};
    await _attempt(failures, 'temporary directory lookup', () async {
      roots.add((await getTemporaryDirectory()).path);
    });
    for (final path in roots) {
      await _deleteMatchingChildren(
        failures,
        Directory(path),
        (name) => _temporaryArtifactNames.any((rule) => rule.hasMatch(name)),
        'temporary Neura artifact deletion',
      );
    }
  }

  static Future<void> _withDirectory(
    List<String> failures,
    String label,
    Future<Directory> Function() resolve,
    Future<void> Function(Directory directory) action,
  ) async {
    Directory? directory;
    await _attempt(failures, label, () async {
      directory = await resolve();
    });
    if (directory != null) await action(directory!);
  }

  static Future<void> _deleteMatchingChildren(
    List<String> failures,
    Directory parent,
    bool Function(String name) matches,
    String label,
  ) async {
    if (!await parent.exists()) return;
    try {
      await for (final entity in parent.list(followLinks: false)) {
        final name = _baseName(entity.path);
        if (matches(name)) {
          await _deleteExact(failures, entity.path, '$label ($name)');
        }
      }
    } catch (_) {
      failures.add(label);
    }
  }

  static Future<void> _deleteExact(
    List<String> failures,
    String path,
    String label,
  ) async {
    await _attempt(failures, label, () async {
      final type = await FileSystemEntity.type(path, followLinks: false);
      switch (type) {
        case FileSystemEntityType.file:
          await File(path).delete();
          break;
        case FileSystemEntityType.directory:
          await Directory(path).delete(recursive: true);
          break;
        case FileSystemEntityType.link:
          await Link(path).delete();
          break;
        case FileSystemEntityType.notFound:
          return;
        default:
          throw FileSystemException('Unsupported app-data entity type.');
      }
      if (await FileSystemEntity.type(path, followLinks: false) !=
          FileSystemEntityType.notFound) {
        throw FileSystemException('App-data deletion could not be verified.');
      }
    });
  }

  static Future<void> _attempt(
    List<String> failures,
    String label,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (!failures.contains(label)) failures.add(label);
    }
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final slash = normalized.lastIndexOf('/');
    return slash < 0 ? normalized : normalized.substring(slash + 1);
  }
}
