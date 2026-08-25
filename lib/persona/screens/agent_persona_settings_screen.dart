import 'package:flutter/material.dart';

import '../agents/agent_persona_catalog.dart';
import '../services/agent_selection_service.dart';
import 'persona_tuning_screen.dart';

/// Consolidated persona settings: which agent answers chat (Auto or an
/// explicit pick), plus the shared tone sliders every agent uses.
class AgentPersonaSettingsScreen extends StatefulWidget {
  const AgentPersonaSettingsScreen({super.key});

  @override
  State<AgentPersonaSettingsScreen> createState() =>
      _AgentPersonaSettingsScreenState();
}

class _AgentPersonaSettingsScreenState
    extends State<AgentPersonaSettingsScreen> {
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await AgentSelectionService.instance.load();
    if (!mounted) return;
    setState(() => _loaded = true);
  }

  Future<void> _select(String? agentId) async {
    await AgentSelectionService.instance.setExplicitAgent(agentId);
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final auto = AgentSelectionService.instance.isAuto;
    final explicitId = AgentSelectionService.instance.explicitAgentId;

    return Scaffold(
      appBar: AppBar(title: const Text("Neura's Personas")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Neura can focus as a few different specialists depending on '
            'what you\'re doing, or you can pick one yourself.',
          ),
          const SizedBox(height: 16),
          Card(
            child: ListTile(
              leading: const Icon(Icons.auto_mode),
              title: const Text('Auto'),
              subtitle: const Text(
                  'Matches whichever room you\'re in (Mood Den, Reflection Bay, Legacy Vault, ...)'),
              trailing: auto ? const Icon(Icons.check) : null,
              onTap: () => _select(null),
            ),
          ),
          for (final agent in AgentPersonaCatalog.all)
            if (!agent.isInternal)
              Card(
                child: ListTile(
                  leading: Icon(agent.icon),
                  title: Text(agent.displayName),
                  subtitle: Text(agent.tagline),
                  trailing: (!auto && explicitId == agent.id)
                      ? const Icon(Icons.check)
                      : null,
                  onTap: () => _select(agent.id),
                ),
              ),
          const SizedBox(height: 24),
          Text('Shared tone', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'Applies to every agent above -- they differ in focus, not in how warm, direct, funny, energetic, or deep Neura sounds.',
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: const Icon(Icons.tune),
              title:
                  const Text('Tune warmth, directness, humor, energy, depth'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const PersonaTuningScreen(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
