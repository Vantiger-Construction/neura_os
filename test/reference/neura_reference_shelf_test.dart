import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reference/neura_reference_shelf.dart';
import 'package:neuro_companion/services/neura_selected_context.dart';

void main() {
  late NeuraReferenceShelf shelf;
  setUp(() {
    shelf = NeuraReferenceShelf();
    shelf.select(NeuraSelectedContext.fromBytes(
        'manual.txt',
        utf8.encode(
            'Introduction\nClean the filter every month.\nUse cold water to clean the filter.\nDisconnect power first.')));
  });
  tearDown(() => shelf.dispose());
  test('retrieval returns exact source passages and original line numbers', () {
    final found = shelf.find('How do I clean the filter?');
    expect(found, hasLength(2));
    expect(found.first.line, 2);
    expect(found.first.text, 'Clean the filter every month.');
    expect(found.last.line, 3);
    expect(shelf.find('Does it support Bluetooth?'), isEmpty);
  });
  test('only explicit single-use local grants can carry selected passages', () {
    expect(() => shelf.authorize('filter', directUserGesture: false),
        throwsStateError);
    final grant = shelf.authorize('filter', directUserGesture: true);
    final prompt = grant.consume();
    expect(prompt, contains('[1] Clean the filter every month.'));
    expect(prompt, isNot(contains('Introduction')));
    expect(utf8.encode(prompt).length, lessThanOrEqualTo(1500));
    expect(() => grant.consume(), throwsStateError);
    expect(grant.hasValidCitations('Monthly [1].'), true);
    expect(grant.hasValidCitations('Monthly [99].'), false);
    expect(grant.hasValidCitations('Trust me.'), false);
  });
  test('source removal and replacement invalidate grants and pending answers',
      () {
    final grant = shelf.authorize('filter', directUserGesture: true);
    var changes = 0;
    shelf.addListener(() => changes++);
    shelf.clear();
    expect(changes, 1);
    expect(shelf.find('filter'), isEmpty);
    expect(grant.requireCurrent, throwsStateError);
    shelf.select(NeuraSelectedContext.fromBytes(
        'other.txt', utf8.encode('Filter replacement.')));
    expect(grant.requireCurrent, throwsStateError);
  });
}
