import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reference/neura_reference_shelf.dart';
import 'package:neuro_companion/services/neura_selected_context.dart';

void main() {
  late NeuraReferenceShelf shelf;
  setUp(() => shelf = NeuraReferenceShelf());
  tearDown(() => shelf.dispose());
  void select(String text) => shelf.select(
      NeuraSelectedContext.fromBytes('synthetic.txt', utf8.encode(text)));

  test('phrase search is literal, case insensitive and preserves exact text',
      () {
    select('Use [A+B] only.\nUse A and B.\nuse [a+b] again.');
    final passages = shelf.find('[a+b]', mode: NeuraReferenceSearchMode.phrase);
    expect(passages.map((p) => p.line), [1, 3]);
    expect(passages.first.text, 'Use [A+B] only.');
    expect(shelf.find('A B', mode: NeuraReferenceSearchMode.phrase), isEmpty);
  });

  test('matches a phrase crossing a normal 220-character boundary', () {
    select('${'x' * 210} clean the filter monthly ${'y' * 220}');
    final passage = shelf
        .find('clean the filter', mode: NeuraReferenceSearchMode.phrase)
        .single;
    expect(passage.text, contains('clean the filter'));
    expect(passage.text.length, lessThanOrEqualTo(220));
  });

  test('phrase bounds and three-passage cap remain enforced', () {
    select(List.filled(10, 'The filter is clean.').join('\n'));
    expect(
        shelf.find('the', mode: NeuraReferenceSearchMode.phrase), hasLength(3));
    expect(shelf.find('', mode: NeuraReferenceSearchMode.phrase), isEmpty);
    expect(
        shelf.find('x' * 161, mode: NeuraReferenceSearchMode.phrase), isEmpty);
    expect(shelf.find('filter\nis', mode: NeuraReferenceSearchMode.phrase),
        isEmpty);
  });

  test('surrounding lines never silently expand an approved model request', () {
    select(
        'Private surrounding note.\nClean the filter monthly.\nOther context.');
    final passage = shelf.find('clean filter').single;
    expect(shelf.contextAround(passage.line).map((l) => l.number), [1, 2, 3]);
    final grant = shelf.authorize('clean filter', directUserGesture: true);
    final prompt = grant.consume();
    expect(prompt, contains('Clean the filter monthly.'));
    expect(prompt, isNot(contains('Private surrounding note')));
    expect(prompt, isNot(contains('Other context')));
  });

  test('phrase approval matches the displayed mode and clears with its source',
      () {
    select('Clean monthly filter.\nClean the filter monthly.');
    final displayed =
        shelf.find('the filter', mode: NeuraReferenceSearchMode.phrase);
    final grant = shelf.authorize('the filter',
        directUserGesture: true, mode: NeuraReferenceSearchMode.phrase);
    expect(grant.passages.map((p) => p.text), displayed.map((p) => p.text));
    shelf.clear();
    expect(shelf.contextAround(2), isEmpty);
    expect(() => grant.consume(), throwsStateError);
  });
}
