import 'package:flutter/material.dart';
import '../neura_bridge/neura_bridge.dart';

class NeuraControlPanel extends StatefulWidget {
  /// Windows only: where the Unity EXE lives on disk.
  final String? unityExePath;

  const NeuraControlPanel({super.key, this.unityExePath});

  @override
  State<NeuraControlPanel> createState() => _NeuraControlPanelState();
}

class _NeuraControlPanelState extends State<NeuraControlPanel> {
  late final NeuraBridge bridge;

  String mood = "calm";
  double energy = 0.7;
  String room = "JoyLounge";

  final log = <String>[];

  @override
  void initState() {
    super.initState();
    bridge = NeuraBridge.forPlatform(unityExePath: widget.unityExePath);
    bridge.onEvent((e) {
      setState(() => log.insert(0, "EVENT: $e"));
    });
    bridge.start().catchError((err) {
      setState(() => log.insert(0, "BRIDGE ERROR: $err"));
    });
  }

  void _push(String line) => setState(() => log.insert(0, line));

  @override
  Widget build(BuildContext context) {
    final rooms = const ["JoyLounge", "MoodDen", "ReflectionBay"];
    final moods = const ["calm", "happy", "anxious", "focused", "sad"];

    return Scaffold(
      appBar: AppBar(title: const Text("Neura Control Panel (Unity-first)")),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: room,
                    items: rooms
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => setState(() => room = v ?? room),
                    decoration: const InputDecoration(labelText: "Room"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: mood,
                    items: moods
                        .map((m) => DropdownMenuItem(value: m, child: Text(m)))
                        .toList(),
                    onChanged: (v) => setState(() => mood = v ?? mood),
                    decoration: const InputDecoration(labelText: "Mood"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text("Energy"),
                Expanded(
                  child: Slider(
                    value: energy,
                    onChanged: (v) => setState(() => energy = v),
                  ),
                ),
                SizedBox(width: 60, child: Text(energy.toStringAsFixed(2))),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                ElevatedButton(
                  onPressed: () async {
                    await bridge.sendSetState(
                        mood: mood, energy: energy, room: room);
                    _push(
                        "SEND SET_STATE mood=$mood energy=$energy room=$room");
                  },
                  child: const Text("Apply State"),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await bridge.sendAction("GO_TO_ROOM", room);
                    _push("SEND ACTION GO_TO_ROOM $room");
                  },
                  child: const Text("Go To Room"),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await bridge.sendAction("PLAY_ANIM", "wave");
                    _push("SEND ACTION PLAY_ANIM wave");
                  },
                  child: const Text("Wave"),
                ),
                OutlinedButton(
                  onPressed: () async {
                    await bridge.sendAction("PLAY_ANIM", "nod");
                    _push("SEND ACTION PLAY_ANIM nod");
                  },
                  child: const Text("Nod"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text("Bridge Log",
                  style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.all(10),
                child: ListView.builder(
                  itemCount: log.length,
                  itemBuilder: (_, i) => Text(log[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
