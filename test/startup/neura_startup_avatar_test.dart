import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/startup/neura_startup_avatar.dart';

class _ArtworkBundle extends CachingAssetBundle {
  _ArtworkBundle({this.missing = false});

  final bool missing;
  int artworkLoads = 0;

  @override
  Future<ByteData> load(String key) async {
    if (key == 'AssetManifest.bin') {
      return const StandardMessageCodec().encodeMessage(<String, dynamic>{})!;
    }
    artworkLoads++;
    if (missing) throw StateError('Artwork unavailable');
    final bytes = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYGBgAAAABQABpfZFQAAAAABJRU5ErkJggg==',
    );
    return ByteData.sublistView(bytes);
  }
}

Widget _host(
  _ArtworkBundle bundle, {
  bool animate = true,
  bool reduceMotion = false,
  bool tickerEnabled = true,
  double pixelRatio = 1,
}) =>
    MaterialApp(
      home: DefaultAssetBundle(
        bundle: bundle,
        child: MediaQuery(
          data: MediaQueryData(
            disableAnimations: reduceMotion,
            devicePixelRatio: pixelRatio,
          ),
          child: TickerMode(
            enabled: tickerEnabled,
            child: Center(child: NeuraStartupAvatar(animate: animate)),
          ),
        ),
      ),
    );

double _verticalOffset(WidgetTester tester) => tester
    .widget<Transform>(
      find
          .descendant(
            of: find.byType(NeuraStartupAvatar),
            matching: find.byType(Transform),
          )
          .first,
    )
    .transform
    .storage[13];

void main() {
  testWidgets('high pixel density keeps the image decode bounded', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_ArtworkBundle(), animate: false, pixelRatio: 12),
    );
    await tester.pumpAndSettle();
    final provider = tester.widget<Image>(find.byType(Image)).image;
    expect(provider, isA<ResizeImage>());
    expect((provider as ResizeImage).height, 1024);
    expect(tester.takeException(), isNull);
  });

  testWidgets('breathes without rebuilding or reloading the artwork', (
    tester,
  ) async {
    final bundle = _ArtworkBundle();
    await tester.pumpWidget(_host(bundle, animate: false));
    await tester.pumpAndSettle();
    final loads = bundle.artworkLoads;

    await tester.pumpWidget(_host(bundle));
    final image = tester.widget<Image>(find.byType(Image));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_verticalOffset(tester), lessThan(0));
    expect(identical(tester.widget<Image>(find.byType(Image)), image), isTrue);
    expect(bundle.artworkLoads, loads);
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion and disabled animation stop frame scheduling', (
    tester,
  ) async {
    final bundle = _ArtworkBundle();
    await tester.pumpWidget(_host(bundle));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_verticalOffset(tester), lessThan(0));

    await tester.pumpWidget(_host(bundle, reduceMotion: true));
    await tester.pumpAndSettle();
    expect(_verticalOffset(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(_host(bundle, animate: false));
    await tester.pumpAndSettle();
    expect(_verticalOffset(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('covered routes stop motion and resume without replaying time', (
    tester,
  ) async {
    final bundle = _ArtworkBundle();
    await tester.pumpWidget(_host(bundle));
    await tester.pump(const Duration(milliseconds: 700));

    await tester.pumpWidget(_host(bundle, tickerEnabled: false));
    await tester.pumpAndSettle();
    expect(_verticalOffset(tester), 0);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await tester.pumpWidget(_host(bundle));
    await tester.pump(const Duration(milliseconds: 700));
    expect(_verticalOffset(tester), lessThan(0));
  });

  testWidgets('background lifecycle states stop motion; disposal is safe', (
    tester,
  ) async {
    final bundle = _ArtworkBundle();
    await tester.pumpWidget(_host(bundle));
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
      await tester.pumpAndSettle();
      expect(_verticalOffset(tester), 0);
      expect(tester.binding.hasScheduledFrame, isFalse);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(_verticalOffset(tester), lessThan(0));
    }

    await tester.pumpWidget(const SizedBox.shrink());
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('missing artwork remains usable with a static fallback', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(_ArtworkBundle(missing: true), animate: false),
    );
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.face_rounded), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
