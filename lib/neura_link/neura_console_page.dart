import 'package:flutter/material.dart';
import 'brain_link.dart';
import 'conversation_controller.dart';
import 'sidecar_manager.dart';
import 'widgets/diagnostics_panel.dart';
import 'widgets/streaming_chat_view.dart';

class NeuraConsolePage extends StatefulWidget {
  const NeuraConsolePage({super.key, required this.brainUrl, this.sidecarExePath, this.onDispatchIntent});
  final String brainUrl; final String? sidecarExePath; final ValueChanged<Map<String, dynamic>>? onDispatchIntent;
  @override State<NeuraConsolePage> createState() => _NeuraConsolePageState();
}
class _NeuraConsolePageState extends State<NeuraConsolePage> {
  late final BrainLink link; late final ConversationController controller; SidecarManager? sidecar;
  @override void initState() {
    super.initState();
    if (widget.sidecarExePath case final path?) { sidecar = SidecarManager(executablePath: path)..start(); }
    link = BrainLink(url: widget.brainUrl)..start();
    controller = ConversationController(link: link, onDispatchIntent: widget.onDispatchIntent);
  }
  @override void dispose() { controller.dispose(); link.dispose(); sidecar?.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Neura Console'), actions: [StreamBuilder<BrainConnectionState>(stream: link.states, builder: (context, snapshot) => Padding(
      padding: const EdgeInsets.all(16), child: Icon(Icons.circle, size: 12, color: link.isConnected ? Colors.green : Colors.red),
    ))]),
    body: Column(children: [Expanded(child: StreamingChatView(controller: controller)), ExpansionTile(title: const Text('Diagnostics'), children: [DiagnosticsPanel(controller: controller)])]),
  );
}

