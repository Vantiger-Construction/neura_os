import 'package:flutter/material.dart';
import '../../core/memory/visual/memory_timeline_node.dart';

class MemoryConstellationView extends StatelessWidget {
  final List<MemoryTimelineNode> nodes;

  const MemoryConstellationView({super.key, required this.nodes});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: nodes.map((n) {
        return Positioned(
          left: n.x * MediaQuery.of(context).size.width,
          top: n.y * MediaQuery.of(context).size.height,
          child: GestureDetector(
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Memory'),
                  content: Text(n.memory.content),
                ),
              );
            },
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.blueAccent.withValues(alpha: 0.7),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
