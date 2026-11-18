import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:neuro_companion/services/auth_service.dart';

void main() {
  test(
      'cloud identity requires email verification independently of local entry',
      () {
    User account({String? confirmed}) => User(
        id: 'synthetic-owner',
        appMetadata: const {},
        userMetadata: const {},
        aud: 'authenticated',
        createdAt: '2026-11-18T00:00:00Z',
        emailConfirmedAt: confirmed);
    expect(verifiedAccountUser(null), isNull);
    expect(verifiedAccountUser(account()), isNull);
    final confirmed = account(confirmed: '2026-11-18T00:00:00Z');
    expect(verifiedAccountUser(confirmed), same(confirmed));
  });
}
