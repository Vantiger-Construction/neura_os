import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:neuro_companion/services/update_check_service.dart';

void main() {
  test('returns only user-initiated manifest updates', () async {
    final service = UpdateCheckService.forTesting(
      currentTag: 'beta-win64-2026-10-10',
      manifestUrl: 'https://updates.example.com/neura.json',
      client: MockClient(
        (_) async => http.Response(
          '{"schema":1,'
          '"latestTag":"beta-win64-2026-10-11",'
          '"htmlUrl":"https://example.com/neura",'
          '"notes":"Stability updates",'
          '"artifactSha256":"'
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef'
          '",'
          '"files":[{"path":"neuro_companion.exe","bytes":12,'
          '"sha256":"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}],'
          '"userInitiatedInstallOnly":true}',
          200,
        ),
      ),
    );

    final update = await service.checkForUpdate();

    expect(update?.tag, 'beta-win64-2026-10-11');
    expect(update?.userInitiatedInstallOnly, isTrue);
    expect(update?.artifactSha256, hasLength(64));
  });

  test(
    'testable service ignores manifests that allow automatic install',
    () async {
      final service = UpdateCheckService.forTesting(
        currentTag: 'beta-win64-2026-10-10',
        manifestUrl: 'https://updates.example.com/neura.json',
        client: MockClient(
          (_) async => http.Response(
            '{"schema":1,'
            '"latestTag":"beta-win64-2026-10-11",'
            '"htmlUrl":"https://example.com/neura",'
            '"userInitiatedInstallOnly":false}',
            200,
          ),
        ),
      );

      expect(await service.checkForUpdate(), isNull);
    },
  );

  test(
    'testable service rejects link-only manifests without artifact digest',
    () async {
      final service = UpdateCheckService.forTesting(
        currentTag: 'beta-win64-2026-10-10',
        manifestUrl: 'https://updates.example.com/neura.json',
        client: MockClient(
          (_) async => http.Response(
            '{"schema":1,'
            '"latestTag":"beta-win64-2026-10-11",'
            '"htmlUrl":"https://example.com/neura",'
            '"userInitiatedInstallOnly":true}',
            200,
          ),
        ),
      );

      expect(await service.checkForUpdate(), isNull);
    },
  );

  test(
    'default build is inert without dart-defined manifest settings',
    () async {
      final service = UpdateCheckService.forTesting(
        client: MockClient((_) async => http.Response('unreachable', 500)),
      );

      expect(await service.checkForUpdate(), isNull);
    },
  );
}
