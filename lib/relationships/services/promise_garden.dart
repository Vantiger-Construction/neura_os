import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../profiles/local_profile_service.dart';
import '../models/neura_promise.dart';
import 'promise_service.dart';

/// The plant in Neura's penthouse that grows as the user keeps promises.
///
/// Growth only ever moves forward: it counts every promise ever kept, so a
/// dropped or overdue promise never shrinks or wilts it. There is no guilt
/// state to paint.
enum PromiseGardenStage {
  /// No promise kept yet: the pot is empty.
  empty,

  /// One kept promise: a seed has broken the soil.
  seed,

  /// A few kept promises: a small sprout.
  sprout,

  /// A steady habit: a leafy plant.
  leafy,

  /// Many kept promises: the plant is in flower.
  blooming;

  /// Kept promises needed to reach each stage, by index.
  static const thresholds = <int>[0, 1, 3, 7, 15];

  /// The stage for [kept] promises kept in total.
  static PromiseGardenStage forKeptCount(int kept) {
    var stage = empty;
    for (var i = 0; i < values.length; i++) {
      if (kept >= thresholds[i]) stage = values[i];
    }
    return stage;
  }

  /// The stage for a list of promises: only completed ones count.
  static PromiseGardenStage from(Iterable<NeuraPromise> promises) =>
      forKeptCount(
        promises.where((p) => p.status == PromiseStatus.completed).length,
      );

  /// Kept promises still needed for the next stage, or null at [blooming].
  static int? toNextStage(int kept) {
    final stage = forKeptCount(kept);
    if (stage == blooming) return null;
    return thresholds[stage.index + 1] - kept;
  }
}

/// Keeps [stage] current from the promises on this device. Profile sessions
/// never read installation-wide promises and see an empty pot.
class PromiseGardenService {
  PromiseGardenService._();

  static final PromiseGardenService instance = PromiseGardenService._();

  final ValueNotifier<PromiseGardenStage> stage =
      ValueNotifier<PromiseGardenStage>(PromiseGardenStage.empty);

  Future<void>? _refreshing;
  int _generation = 0;

  /// Re-reads promises. Failures leave the garden as it was.
  Future<void> refresh({Future<List<NeuraPromise>> Function()? load}) {
    final pending = _refreshing;
    if (pending != null) return pending;
    final future = _refresh(load ?? PromiseService.instance.all);
    _refreshing = future;
    return future.whenComplete(() => _refreshing = null);
  }

  Future<void> _refresh(Future<List<NeuraPromise>> Function() load) async {
    final generation = _generation;
    if (LocalProfileService.instance.enabled) {
      stage.value = PromiseGardenStage.empty;
      return;
    }
    try {
      final promises = await load();
      if (generation != _generation) return;
      if (LocalProfileService.instance.enabled) {
        stage.value = PromiseGardenStage.empty;
        return;
      }
      stage.value = PromiseGardenStage.from(promises);
    } catch (_) {
      // An unreadable promise list is no reason to change the room.
    }
  }

  /// After a local data wipe the pot is empty again, and a refresh that was
  /// already reading cannot bring the old plant back.
  void reset() {
    _generation += 1;
    stage.value = PromiseGardenStage.empty;
  }
}
