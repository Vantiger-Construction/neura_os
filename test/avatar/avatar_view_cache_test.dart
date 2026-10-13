import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/avatar/avatar_asset.dart';
import 'package:neuro_companion/avatar/avatar_controller.dart';
import 'package:neuro_companion/avatar/avatar_types.dart';
import 'package:neuro_companion/avatar/avatar_view.dart';
import 'package:neuro_companion/avatar/renderers/rive_avatar_view.dart';

const _primary = 'test/avatar.riv';
const _fallback = 'test/fallback.riv';
const _missing = 'test/missing.riv';

AvatarSpec _spec(String path, {String? fallback}) => AvatarSpec(
      id: 'test',
      name: 'Test avatar',
      format: AvatarFormat.rive,
      assetPath: path,
      fallbackAssetPath: fallback,
    );

Widget _host(
  AvatarSpec spec,
  AvatarController controller, {
  double size = 128,
}) =>
    MaterialApp(
      home: Center(
        child: AvatarView(spec: spec, controller: controller, size: size),
      ),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late Map<String, int> reads;
  Completer<ByteData?>? pendingPrimary;

  setUp(() {
    reads = {};
    pendingPrimary = null;
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets', (
      message,
    ) async {
      final path = const StringCodec().decodeMessage(message)!;
      reads.update(path, (value) => value + 1, ifAbsent: () => 1);
      if (path == _missing) return null;
      if (path == _primary && pendingPrimary != null) {
        return pendingPrimary!.future;
      }
      return ByteData.sublistView(Uint8List.fromList([1]));
    });
  });

  tearDown(() {
    binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      null,
    );
  });

  testWidgets('parent, size and controller changes reuse asset resolution', (
    tester,
  ) async {
    final controller = AvatarController();
    final replacement = AvatarController();
    addTearDown(controller.dispose);
    addTearDown(replacement.dispose);
    await tester.pumpWidget(_host(_spec(_primary), controller));
    await tester.pumpAndSettle();
    expect(reads[_primary], 1);

    // Equivalent specs can be newly constructed by a parent's rebuild.
    await tester.pumpWidget(_host(_spec(_primary), controller, size: 160));
    await tester.pumpAndSettle();
    controller.setTalking(true);
    await tester.pump();
    await tester.pumpWidget(_host(_spec(_primary), replacement, size: 180));
    await tester.pumpAndSettle();

    expect(reads[_primary], 1);
    expect(find.byType(RiveAvatarView), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('missing primary and valid fallback are each probed once', (
    tester,
  ) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(_spec(_missing, fallback: _fallback), controller),
    );
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      _host(_spec(_missing, fallback: _fallback), controller, size: 160),
    );
    await tester.pumpAndSettle();

    expect(reads[_missing], 1);
    expect(reads[_fallback], 1);
    expect(
      tester.widget<RiveAvatarView>(find.byType(RiveAvatarView)).spec.assetPath,
      _fallback,
    );
  });

  testWidgets('a late old probe cannot replace a newly selected avatar', (
    tester,
  ) async {
    final controller = AvatarController();
    addTearDown(controller.dispose);
    final pending = Completer<ByteData?>();
    pendingPrimary = pending;
    await tester.pumpWidget(_host(_spec(_primary), controller));
    await tester.pumpWidget(_host(_spec(_fallback), controller));
    await tester.pumpAndSettle();
    expect(
      tester.widget<RiveAvatarView>(find.byType(RiveAvatarView)).spec.assetPath,
      _fallback,
    );

    pending.complete(ByteData.sublistView(Uint8List.fromList([1])));
    await tester.pumpAndSettle();
    expect(
      tester.widget<RiveAvatarView>(find.byType(RiveAvatarView)).spec.assetPath,
      _fallback,
    );
    expect(reads[_primary], 1);
    expect(reads[_fallback], 1);
    expect(tester.takeException(), isNull);
  });
}
