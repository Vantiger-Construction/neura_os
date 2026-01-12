# Integration Guide

## 1) Copy files
Copy `core/lib/creator_engine/` into your Flutter app at the same path.

## 2) Add route
```dart
routes: {
  '/creator': (ctx) {
    final item = ModalRoute.of(ctx)!.settings.arguments as NeuraContentItem;
    return NeuraCreatorScreen(
      item: item,
      onOutcome: (o) => engine.logOutcome(item: item, outcome: o),
    );
  },
}
```

## 3) Provide adapters (recommended)
Implement the ports with your existing services:

```dart
class MemoryGraphAdapter implements MemoryGraphPort {
  final MemoryGraphService svc;
  MemoryGraphAdapter(this.svc);

  @override
  Future<Map<String, dynamic>> getRecentSignals({Duration window = const Duration(days: 7)}) async {
    return svc.getRecentSignals(window: window);
  }

  @override
  Future<void> logEvent(String type, Map<String, dynamic> payload) async {
    await svc.logEvent(type, payload);
  }
}

class GuardrailsAdapter implements GuardrailsPort {
  final NeuraGuardrails guard;
  GuardrailsAdapter(this.guard);

  @override
  Future<Map<String, dynamic>?> approveContent(Map<String, dynamic> draft) async {
    return guard.approveContent(draft);
  }
}
```

## 4) Generate + show
```dart
final engine = NeuraCreatorEngine(
  memory: MemoryGraphAdapter(memoryGraphService),
  guardrails: GuardrailsAdapter(guardrails),
);

final item = await engine.generate();
if (item != null) {
  Navigator.pushNamed(context, '/creator', arguments: item);
}
```
