import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/reference/neura_reference_shelf.dart';
import 'package:neuro_companion/services/neura_selected_context.dart';

void main() {
  late NeuraReferenceShelf shelf;
  late NeuraReferenceGrant grant;
  const first = 'Use 2 litres of cold water to clean the filter monthly.';
  const second =
      'Do not clean the filter daily unless the warning light is on.';
  const third = 'Filter label: "café"; path C:\\parts; ≤2 litres.';
  String quotes(List<Map<String, Object>> entries) =>
      jsonEncode({'quotes': entries});
  Map<String, Object> quote(int number, String text) =>
      {'passage': number, 'text': text};

  setUp(() {
    shelf = NeuraReferenceShelf()
      ..select(NeuraSelectedContext.fromBytes('manual.txt',
          utf8.encode('Private unrelated line.\n$first\n$second\n$third')));
    grant = shelf.authorize('filter', directUserGesture: true);
  });
  tearDown(() => shelf.dispose());

  test(
      'exact quotations preserve quantities, conditions, Unicode and source lines',
      () {
    final result = grant.formatVerifiedReply(
        quotes([quote(1, first), quote(2, second), quote(3, third)]));
    expect(result, contains('[1] line 2\n$first'));
    expect(result, contains('[2] line 3\n$second'));
    expect(result, contains('[3] line 4\n$third'));
    expect(result,
        contains('cannot establish whether these excerpts fully answer'));
    expect(result, contains('an exact quotation is not a verified fact'));
    expect(result, isNot(contains('Private unrelated line')));
  });

  for (final entry in {
    'incorrect quantity': [
      quote(1, first.replaceFirst('2 litres', '20 litres'))
    ],
    'incorrect units': [quote(1, first.replaceFirst('litres', 'gallons'))],
    'incorrect frequency': [quote(1, first.replaceFirst('monthly', 'daily'))],
    'negation removed': [quote(2, second.replaceFirst('Do not', 'Do'))],
    'partial quote drops a condition': [
      quote(2, 'Do not clean the filter daily')
    ],
    'substring changes meaning': [quote(2, 'clean the filter daily')],
    'fabricated addition': [quote(1, '$first Replace it yearly.')],
    'partial support mixed with an exact quote': [
      quote(1, first),
      quote(2, 'Clean the filter daily.')
    ],
    'wrong attribution': [quote(2, first)],
    'unknown passage': [quote(99, first)],
    'duplicate passage': [quote(1, first), quote(1, first)],
    'empty evidence': <Map<String, Object>>[],
  }.entries) {
    test('rejects ${entry.key} in full', () {
      expect(grant.formatVerifiedReply(quotes(entry.value)),
          NeuraReferenceGrant.unverifiedReply);
    });
  }

  for (final response in <Object?>[
    null,
    [],
    {'quotes': null},
    {'quotes': 'Clean the filter monthly [1].'},
    {
      'quotes': [null]
    },
    {
      'quotes': [
        {'passage': '1', 'text': first}
      ]
    },
    {
      'quotes': [
        {'passage': 1.0, 'text': first}
      ]
    },
    {
      'quotes': [
        {
          'passage': 1,
          'text': [first]
        }
      ]
    },
    {
      'quotes': [
        {'passage': 1, 'text': first, 'answer': 'Clean daily [1].'}
      ]
    },
    {
      'quotes': [quote(1, first)],
      'answer': 'Clean daily [1].'
    },
  ].indexed) {
    test('withholds malformed or extra model content ${response.$1}', () {
      expect(grant.formatVerifiedReply(jsonEncode(response.$2)),
          NeuraReferenceGrant.unverifiedReply);
    });
  }

  test('withholds prose, wrappers, truncated JSON and excessive output', () {
    for (final response in [
      'Clean the filter daily [1].',
      '```json\n${quotes([quote(1, first)])}\n```',
      '${quotes([quote(1, first)])}\nClean the filter daily [1].',
      '{"quotes":[',
      ' ' * 4097,
    ]) {
      expect(grant.formatVerifiedReply(response),
          NeuraReferenceGrant.unverifiedReply);
    }
  });

  test('conflicting exact excerpts remain attributed with explicit uncertainty',
      () {
    shelf.select(NeuraSelectedContext.fromBytes('conflicting.txt',
        utf8.encode('Clean the filter monthly.\nClean the filter daily.')));
    final conflicting = shelf.authorize('filter', directUserGesture: true);
    final result = conflicting.formatVerifiedReply(quotes([
      quote(1, 'Clean the filter monthly.'),
      quote(2, 'Clean the filter daily.')
    ]));
    expect(result, contains('[1] line 1\nClean the filter monthly.'));
    expect(result, contains('[2] line 2\nClean the filter daily.'));
    expect(result,
        contains('cannot establish whether these excerpts fully answer'));
  });

  test('irrelevant but exact text never receives a completeness claim', () {
    final result = grant.formatVerifiedReply(quotes([quote(3, third)]));
    expect(result, contains(third));
    expect(result,
        contains('cannot establish whether these excerpts fully answer'));
  });

  test('revoked, replaced and disposed sources cannot format late replies', () {
    final response = quotes([quote(1, first)]);
    grant.revoke();
    expect(() => grant.formatVerifiedReply(response), throwsStateError);
    final replaced = shelf.authorize('filter', directUserGesture: true);
    shelf.clear();
    expect(() => replaced.formatVerifiedReply(response), throwsStateError);
    shelf.dispose();
    expect(() => grant.formatVerifiedReply(response), throwsStateError);
    shelf = NeuraReferenceShelf();
  });
}
