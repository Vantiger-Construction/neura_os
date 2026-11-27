import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/relationships/services/promise_catcher.dart';

void main() {
  String? catchIn(String message) => PromiseCatcher.commitmentFrom(message);

  test('finds a small commitment and trims it to the promise', () {
    expect(catchIn("I'll call my sister tonight."), 'Call my sister tonight');
    expect(catchIn('Remind me to drink water'), 'Drink water');
    expect(
      catchIn('ok I will go for a walk after lunch!'),
      'Go for a walk after lunch',
    );
    expect(
      catchIn('Tomorrow I’ll finish the report, but I am tired'),
      'Finish the report',
    );
    expect(
      catchIn('I need to pay rent by friday because it is due'),
      'Pay rent by friday',
    );
  });

  test('ignores questions, hedges and messages without a commitment', () {
    expect(catchIn('Should I call her?'), isNull);
    expect(catchIn('I will call her?'), isNull);
    expect(catchIn('I should probably sleep'), isNull);
    expect(catchIn("I'll be fine"), isNull);
    expect(catchIn("I'll never be good enough"), isNull);
    expect(catchIn('I am so ill today'), isNull);
    expect(catchIn('Thanks, that helped'), isNull);
    expect(catchIn(''), isNull);
  });

  test('never offers anything about harm as a promise', () {
    expect(catchIn("I want to die and I'll end it"), isNull);
    expect(catchIn("I'll hurt myself tonight"), isNull);
  });

  test('keeps the promise short', () {
    final long = "I'll ${List.filled(30, 'really').join(' ')} do it";
    expect(catchIn(long), isNull);
    expect(catchIn("I'll go"), isNull);
  });
}
