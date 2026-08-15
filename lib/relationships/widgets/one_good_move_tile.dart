import 'package:flutter/material.dart';
import '../services/relationship_insight_service.dart';
import '../services/feedback_service.dart';
import '../models/relationship_suggestion.dart';

class OneGoodMoveTile extends StatefulWidget {
  final List<int> recentMoods;
  final bool promisesOutstanding;
  final int? daysSinceLastContact;
  final void Function(RelationshipSuggestion suggestion) onAction;

  const OneGoodMoveTile({
    super.key,
    required this.recentMoods,
    required this.promisesOutstanding,
    this.daysSinceLastContact,
    required this.onAction,
  });

  @override
  State<OneGoodMoveTile> createState() => _OneGoodMoveTileState();
}

class _OneGoodMoveTileState extends State<OneGoodMoveTile> {
  bool _showWhy = false;

  @override
  Widget build(BuildContext context) {
    final service = const RelationshipInsightService();
    final suggestion = service.computeOneGoodMove(
      recentMoods: widget.recentMoods,
      promisesOutstanding: widget.promisesOutstanding,
      daysSinceLastContact: widget.daysSinceLastContact,
    );

    if (suggestion == null) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              suggestion.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(suggestion.description),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () {
                    setState(() => _showWhy = !_showWhy);
                  },
                  child: Text(_showWhy ? 'Hide why' : 'Why this?'),
                ),
                ElevatedButton(
                  onPressed: () => widget.onAction(suggestion),
                  child: Text(suggestion.actionLabel),
                ),
              ],
            ),
            if (_showWhy && suggestion.reasons.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...suggestion.reasons.map(
                (r) => Text(
                  '• $r',
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
            ],
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  tooltip: "Helpful",
                  icon: const Icon(Icons.thumb_up_alt_outlined),
                  onPressed: () {
                    FeedbackService.instance.addFeedback(suggestion.title, 1);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Thanks, I'll remember that helped."),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: "Not helpful",
                  icon: const Icon(Icons.thumb_down_alt_outlined),
                  onPressed: () {
                    FeedbackService.instance.addFeedback(suggestion.title, -1);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Got it, I'll suggest that less."),
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
