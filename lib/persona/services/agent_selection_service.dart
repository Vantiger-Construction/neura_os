import 'package:flutter/foundation.dart';

import '../../neura_shell/models/neura_room.dart';
import '../../shared/services/self_heal_service.dart';
import '../../startup/neura_prefs_cache.dart';
import '../agents/agent_persona_catalog.dart';
import '../models/agent_persona.dart';

/// Which agent persona answers the next chat turn. "Auto" (the default)
/// follows the current [NeuraRoom]; an explicit choice overrides that until
/// the user picks "Auto" again.
class AgentSelectionService extends ChangeNotifier {
  AgentSelectionService._internal();
  static final AgentSelectionService instance =
      AgentSelectionService._internal();

  static const _keyExplicitAgent = 'neura_active_agent_override_v1';

  final _selfHeal = SelfHealService.instance;

  String? _explicitAgentId;
  bool get isAuto => _explicitAgentId == null;

  /// The raw explicit override id, or null if "Auto". Unlike [resolveAgent],
  /// this doesn't need a room and doesn't fall back to General.
  String? get explicitAgentId => _explicitAgentId;

  Future<void> load() async {
    try {
      final prefs = NeuraPrefsCache.prefs;
      _explicitAgentId = prefs.getString(_keyExplicitAgent);
    } catch (e, st) {
      await _selfHeal.recordError('AgentSelectionService.load', e, st);
      _explicitAgentId = null;
    }
  }

  /// Resolves which non-internal agent should answer for [room] right now.
  AgentPersona resolveAgent(NeuraRoom room) {
    final explicit = _explicitAgentId;
    if (explicit != null) return AgentPersonaCatalog.byId(explicit);
    return AgentPersonaCatalog.defaultFor(room);
  }

  /// Pass `null` to go back to "Auto" (follow the room).
  Future<void> setExplicitAgent(String? agentId) async {
    _explicitAgentId = agentId;
    notifyListeners();
    try {
      final prefs = NeuraPrefsCache.prefs;
      if (agentId == null) {
        await prefs.remove(_keyExplicitAgent);
      } else {
        await prefs.setString(_keyExplicitAgent, agentId);
      }
    } catch (e, st) {
      await _selfHeal.recordError('AgentSelectionService.setExplicitAgent', e, st);
    }
  }

  void resetAfterDataWipe() {
    _explicitAgentId = null;
    notifyListeners();
  }
}
