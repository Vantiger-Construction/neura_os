import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/models/journal_entry.dart';
import 'package:neuro_companion/services/conflict_resolution_service.dart';

JournalEntry entry({
  required String content,
  DateTime? updatedAt,
}) {
  return JournalEntry(
    id: 'same-id',
    timestamp: DateTime.utc(2026, 1, 1),
    updatedAt: updatedAt,
    content: content,
  );
}

void main() {
  final service = ConflictResolutionService();

  test('newer remote revision wins even when original timestamps match', () {
    final decision = service.decide(
      entry(content: 'local', updatedAt: DateTime.utc(2026, 1, 2)),
      entry(content: 'remote', updatedAt: DateTime.utc(2026, 1, 3)),
    );

    expect(decision.winner, ConflictWinner.remote);
    expect(decision.entry.content, 'remote');
    expect(decision.hadDivergentContent, isTrue);
  });

  test('newer local revision remains authoritative', () {
    final decision = service.decide(
      entry(content: 'local', updatedAt: DateTime.utc(2026, 1, 4)),
      entry(content: 'remote', updatedAt: DateTime.utc(2026, 1, 3)),
    );

    expect(decision.winner, ConflictWinner.local);
    expect(decision.entry.content, 'local');
  });

  test('equal-time divergent revisions fail safe to local data', () {
    final time = DateTime.utc(2026, 1, 4);
    final decision = service.decide(
      entry(content: 'local', updatedAt: time),
      entry(content: 'remote', updatedAt: time),
    );

    expect(decision.winner, ConflictWinner.local);
    expect(decision.entry.content, 'local');
    expect(decision.hadDivergentContent, isTrue);
  });

  test('legacy entries fall back to original timestamp', () {
    final decision = service.decide(
      entry(content: 'legacy local'),
      entry(content: 'new remote', updatedAt: DateTime.utc(2026, 1, 2)),
    );

    expect(decision.winner, ConflictWinner.remote);
  });
}
