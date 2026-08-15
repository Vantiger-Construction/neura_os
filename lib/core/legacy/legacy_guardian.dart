import 'legacy_entry.dart';
import 'legacy_policy.dart';
import 'legacy_rule.dart';

class LegacyGuardian {
  bool canAccess(LegacyEntry entry, LegacyRule rule) {
    switch (rule.access) {
      case LegacyAccessLevel.ownerOnly:
        return true;
      case LegacyAccessLevel.timedUnlock:
        return rule.unlockAt != null && DateTime.now().isAfter(rule.unlockAt!);
      case LegacyAccessLevel.trustedContact:
        return false; // future external auth
    }
  }
}
