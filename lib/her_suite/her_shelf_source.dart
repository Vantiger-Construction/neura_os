import 'dart:async';

import 'package:flutter/foundation.dart';

import '../intelligence/intelligence_preferences.dart';
import '../intelligence/neura_intelligence_controller.dart';
import '../reliability/safe_boot.dart';
import '../teaching/neura_teaching_preferences.dart';
import '../teaching/neura_teaching_service.dart';

/// What Her Shelf shows: the settings you have taught Neura, as labels only.
///
/// It never holds memories, chats or journals. Those stay behind the Memory
/// screen, which has its own consent and encryption; the shelf only links to
/// it.
@immutable
class HerShelfSummary {
  const HerShelfSummary({
    required this.safeMode,
    required this.teachingAvailable,
    this.teachingUnreadable = false,
    this.answerDetail,
    this.answerIsTemporary = false,
    this.planSize,
    this.planIsTemporary = false,
    required this.suggestions,
    required this.quietHoursEnabled,
    required this.quietHoursStart,
    required this.quietHoursEnd,
  });

  final bool safeMode;
  final bool teachingAvailable;

  /// Teach Neura's saved settings exist but could not be read, so the shelf
  /// must not show them as "not taught".
  final bool teachingUnreadable;
  final NeuraAnswerDetail? answerDetail;
  final bool answerIsTemporary;
  final NeuraPlanSize? planSize;
  final bool planIsTemporary;
  final NeuraProactivityLevel suggestions;
  final bool quietHoursEnabled;
  final int quietHoursStart;
  final int quietHoursEnd;
}

/// Where Her Shelf reads its summary from. Tests use a fake.
abstract class HerShelfSource implements Listenable {
  HerShelfSummary read();

  /// Starts any loading the summary needs. Safe to call more than once.
  void ensureLoaded() {}
}

/// Reads Teach Neura, the intelligence preferences and Safe Mode.
class AppHerShelfSource extends ChangeNotifier implements HerShelfSource {
  AppHerShelfSource({
    NeuraTeachingService? teaching,
    NeuraIntelligenceController? intelligence,
    ValueListenable<bool>? safeMode,
  })  : _teaching = teaching ?? NeuraTeachingService.instance,
        _intelligence = intelligence ?? NeuraIntelligenceController.instance,
        _safeMode = safeMode ?? SafeBoot.instance.safeMode {
    _teaching.addListener(_changed);
    _intelligence.addListener(notifyListeners);
    _safeMode.addListener(_changed);
    _wasAvailable = _teaching.available;
  }

  final NeuraTeachingService _teaching;
  final NeuraIntelligenceController _intelligence;
  final ValueListenable<bool> _safeMode;
  bool _wanted = false;
  bool _wasAvailable = false;

  @override
  void ensureLoaded() {
    _wanted = true;
    _loadTeaching();
    unawaited(_intelligence.initialize().catchError((_) {}));
  }

  // A failed load is reported through the service's `error`, which the
  // summary shows as unreadable, so the future's own error is handled.
  void _loadTeaching() {
    if (_teaching.available && !_teaching.loaded) {
      unawaited(_teaching.load().catchError((_) {}));
    }
  }

  void _changed() {
    // Teach Neura is unavailable in Safe Mode or while hidden. When it comes
    // back with the shelf open, load then: retry once per return, never in a
    // loop after a failed read.
    final available = _teaching.available;
    if (_wanted && available && !_wasAvailable) _loadTeaching();
    _wasAvailable = available;
    notifyListeners();
  }

  @override
  HerShelfSummary read() {
    final teaching = _teaching.loaded ? _teaching.current : null;
    final prefs = _intelligence.preferences;
    return HerShelfSummary(
      safeMode: _safeMode.value,
      teachingAvailable: _teaching.available,
      teachingUnreadable: !_teaching.loaded && _teaching.error != null,
      answerDetail: teaching?.answerDetail,
      answerIsTemporary: teaching != null && _teaching.answerIsTemporary,
      planSize: teaching?.planSize,
      planIsTemporary: teaching != null && _teaching.planIsTemporary,
      suggestions:
          prefs.enabled ? prefs.proactivityLevel : NeuraProactivityLevel.off,
      quietHoursEnabled: prefs.quietHoursEnabled,
      quietHoursStart: prefs.quietHoursStart,
      quietHoursEnd: prefs.quietHoursEnd,
    );
  }

  @override
  void dispose() {
    _teaching.removeListener(_changed);
    _intelligence.removeListener(notifyListeners);
    _safeMode.removeListener(_changed);
    super.dispose();
  }
}
