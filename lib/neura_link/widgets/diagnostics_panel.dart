import 'package:flutter/material.dart';
import '../conversation_controller.dart';

class DiagnosticsPanel extends StatelessWidget {
  const DiagnosticsPanel({super.key, required this.controller});
  final ConversationController controller;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final snapshot = controller.diagnostics;
        return Column(children: [
          ListTile(
              title: const Text('Neura diagnostics'),
              trailing: IconButton(
                  onPressed: controller.link.isConnected
                      ? controller.requestDiagnostics
                      : null,
                  icon: const Icon(Icons.refresh))),
          if (snapshot == null)
            const Padding(
                padding: EdgeInsets.all(24),
                child: Text('Refresh to request a health snapshot.')),
          if (snapshot != null)
            ...snapshot.checks.map((check) => ListTile(
                  leading: Icon(
                      check.isHealthy
                          ? Icons.check_circle
                          : Icons.warning_amber,
                      color: check.isHealthy ? Colors.green : Colors.orange),
                  title: Text(check.name),
                  subtitle: Text(check.isHealthy
                      ? (check.detail ?? check.status)
                      : '${check.detail ?? check.status}\nRemedy: ${check.remedy}'),
                  isThreeLine: !check.isHealthy,
                )),
        ]);
      });
}
