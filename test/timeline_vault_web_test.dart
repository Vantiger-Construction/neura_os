import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reliability/timeline_vault_web.dart';

void main() {
  test('timeline preserves append order and sequence', () async {
    final vault = TimelineVault.instance;
    await vault.append('first');
    await vault.append('second');
    final tail = await vault.tail(maxLines: 2);
    expect(tail.map((event) => event['kind']), ['first', 'second']);
    expect(tail.last['seq'], greaterThan(tail.first['seq'] as int));
  });
}
