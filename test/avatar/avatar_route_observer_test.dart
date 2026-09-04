import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:neuro_companion/avatar/avatar_route_observer.dart';
import 'package:neuro_companion/core/neura_event_bus.dart';
import 'package:neuro_companion/core/neura_events.dart';

// NeuraEventBus.I is a hard singleton (no injectable test double available),
// so these tests listen on the real bus and unsubscribe in tearDown to avoid
// leaking listeners - or captured events - across tests in this file.
//
// bus.on<T>() delivers via a broadcast StreamController, which fires
// listeners asynchronously (on a later microtask), not synchronously inside
// emit(). Every test below awaits pumpEventQueue() after the action under
// test so the listener has actually run before asserting on `captured`.
void main() {
  late AvatarRouteObserver observer;
  late List<NeuraRouteEvent> captured;
  late void Function() unsubscribe;

  setUp(() {
    observer = AvatarRouteObserver(NeuraEventBus.I);
    captured = [];
    unsubscribe = NeuraEventBus.I.on<NeuraRouteEvent>(captured.add);
  });

  tearDown(() {
    unsubscribe();
  });

  PageRoute<void> namedRoute(String name) => MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
        settings: RouteSettings(name: name),
      );

  test("didPush emits a NeuraRouteEvent with the pushed route's name",
      () async {
    observer.didPush(namedRoute('/chat'), null);
    await pumpEventQueue();

    expect(captured, hasLength(1));
    expect(captured.single.routeName, '/chat');
  });

  test("didPush falls back to the route's runtimeType when unnamed", () async {
    final route =
        MaterialPageRoute<void>(builder: (_) => const SizedBox.shrink());
    observer.didPush(route, null);
    await pumpEventQueue();

    expect(captured, hasLength(1));
    expect(captured.single.routeName, route.runtimeType.toString());
  });

  test('didReplace emits an event for the new route', () async {
    observer.didReplace(
      newRoute: namedRoute('/new'),
      oldRoute: namedRoute('/old'),
    );
    await pumpEventQueue();

    expect(captured, hasLength(1));
    expect(captured.single.routeName, '/new');
  });

  test('didPop emits an event for the previous (now-current) route', () async {
    observer.didPop(namedRoute('/popped'), namedRoute('/previous'));
    await pumpEventQueue();

    expect(captured, hasLength(1));
    expect(captured.single.routeName, '/previous');
  });

  test('didPop with no previous route falls back to unknown_route', () async {
    observer.didPop(namedRoute('/only'), null);
    await pumpEventQueue();

    expect(captured, hasLength(1));
    expect(captured.single.routeName, 'unknown_route');
  });
}
