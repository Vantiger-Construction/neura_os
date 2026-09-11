import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:neuro_companion/services/portable_backup_codec.dart';

void main() {
  final codec = PortableBackupCodec(iterations: 120000);
  const payload = {
    'createdAt': '2026-09-11T00:00:00.000Z',
    'journalEntries': [
      {'id': 'entry-1', 'content': 'Private reflection'},
    ],
  };

  test('portable backup round-trips without a device key', () async {
    final encrypted = await codec.encrypt(
      payload: payload,
      passphrase: 'correct horse battery staple',
    );
    final restored = await codec.decrypt(
      envelope: encrypted,
      passphrase: 'correct horse battery staple',
    );

    expect(restored, payload);
    expect(encrypted, isNot(contains('Private reflection')));
  });

  test('wrong passphrase fails authenticated decryption', () async {
    final encrypted = await codec.encrypt(
      payload: payload,
      passphrase: 'correct horse battery staple',
    );

    await expectLater(
      codec.decrypt(
        envelope: encrypted,
        passphrase: 'different secure passphrase',
      ),
      throwsA(isA<SecretBoxAuthenticationError>()),
    );
  });

  test('tampering fails authenticated decryption', () async {
    final encrypted = await codec.encrypt(
      payload: payload,
      passphrase: 'correct horse battery staple',
    );
    final envelope = jsonDecode(encrypted) as Map<String, dynamic>;
    final cipher = (envelope['cipher'] as Map).cast<String, dynamic>();
    final data = cipher['data'] as String;
    cipher['data'] = '${data.substring(0, data.length - 2)}AA';

    await expectLater(
      codec.decrypt(
        envelope: jsonEncode(envelope),
        passphrase: 'correct horse battery staple',
      ),
      throwsA(anything),
    );
  });

  test('short passphrases are rejected', () {
    expect(
      () => codec.encrypt(payload: payload, passphrase: 'too short'),
      throwsArgumentError,
    );
  });
}
