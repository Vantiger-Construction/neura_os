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
    _teaching.addListener(notifyListeners);
    _intelligence.addListener(notifyListeners);
    _safeMode.addListener(notifyListeners);
  }

  final NeuraTeachingService _teaching;
  final NeuraIntelligenceController _intelligence;
  final ValueListenable<bool> _safeMode;

  @override
  void ensureLoaded() {
    if (_teaching.available && !_teaching.loaded) {
      unawaited(_teaching.load().catchError((_) {}));
    }
    unawaited(_intelligence.initialize().catchError((_) {}));
  }

  @override
  HerShelfSummary read() {
    final teaching = _teaching.loaded ? _teaching.current : null;
    final prefs = _intelligence.preferences;
    return HerShelfSummary(
      safeMode: _safeMode.value,
      teachingAvailable: _teaching.available,
      answerDetail: teaching?.answerDetail,
      answerIsTemporary: teaching != null && _teaching.answerIsTemporary,
      planSize: teaching?.planSize,
      planIsTemporary: teaching != null && _teaching.planIsTemporary,
      suggestions: prefs.enabled
          ? prefs.proactivityLevel
          : NeuraProactivityLevel.off,
      quietHoursEnabled: prefs.quietHoursEnabled,
      quietHoursStart: prefs.quietHoursStart,
      quietHoursEnd: prefs.quietHoursEnd,
    );
  }

  @override
  void dispose() {
    _teaching.removeListener(notifyListeners);
    _intelligence.removeListener(notifyListeners);
    _safeMode.removeListener(notifyListeners);
    super.dispose();
  }
}
