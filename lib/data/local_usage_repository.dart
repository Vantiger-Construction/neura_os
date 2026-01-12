import 'package:hive/hive.dart';
import 'package:neura_companion/models/usage_entry.dart';

class LocalUsageRepository {
  static const String _boxName = 'usage_entries';

  Future<Box<UsageEntry>> _getBox() async {
    if (!Hive.isBoxOpen(_boxName)) {
      return await Hive.openBox<UsageEntry>(_boxName);
    }
    return Hive.box<UsageEntry>(_boxName);
  }

  Future<void> saveEntry(UsageEntry entry) async {
    final box = await _getBox();
    await box.put(entry.id, entry);
  }

  Future<List<UsageEntry>> getAllEntries() async {
    final box = await _getBox();
    return box.values.toList();
  }
}