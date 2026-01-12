import 'legacy_policy.dart';

class LegacyRule {
  final LegacyAccessLevel access;
  final DateTime? unlockAt;

  const LegacyRule({
    required this.access,
    this.unlockAt,
  });
}
