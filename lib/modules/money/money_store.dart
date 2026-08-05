import 'money_models.dart';
import '../../core/memory/memory_crypto.dart';
import '../../startup/neura_prefs_cache.dart';

/// Local, encrypted-at-rest income/expense history. Same shape as
/// MoodStore: a single encrypted blob (not JSONL) since the whole list
/// needs to be read anyway to compute a running balance.
class MoneyStore {
  MoneyStore._();
  static final MoneyStore instance = MoneyStore._();

  static const _key = 'neura.money.entries.v1';

  MemoryCrypto? _crypto;
  Future<MemoryCrypto> _ensureCrypto() async {
    _crypto ??= await MemoryCrypto.demo();
    return _crypto!;
  }

  Future<List<MoneyEntry>> getAll() async {
    final prefs = NeuraPrefsCache.prefs;
    final raw = prefs.getString(_key) ?? '';
    if (raw.trim().isEmpty) return <MoneyEntry>[];

    final crypto = await _ensureCrypto();
    try {
      final decrypted = await crypto.decryptJson(raw);
      final items = (decrypted['items'] as List)
          .whereType<Map>()
          .map((m) => MoneyEntry.fromJson(Map<String, Object?>.from(m)))
          .toList()
        ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      return items;
    } catch (_) {
      // Not a valid encrypted blob - either corrupt, or first run.
      return <MoneyEntry>[];
    }
  }

  Future<void> add(MoneyEntry entry) async {
    final items = await getAll();
    items.add(entry);
    await _persist(items);
  }

  Future<void> remove(String id) async {
    final items = await getAll();
    items.removeWhere((e) => e.id == id);
    await _persist(items);
  }

  Future<void> _persist(List<MoneyEntry> items) async {
    final crypto = await _ensureCrypto();
    final blob = await crypto.encryptJson({'items': items.map((e) => e.toJson()).toList()});
    await NeuraPrefsCache.prefs.setString(_key, blob);
  }

  Future<double> balance() async {
    final items = await getAll();
    return items.fold<double>(0, (sum, e) => sum + e.signedAmount);
  }

  /// Totals for the current calendar month.
  Future<({double income, double expense})> thisMonthSummary() async {
    final items = await getAll();
    final now = DateTime.now();
    final thisMonth = items.where((e) => e.timestamp.year == now.year && e.timestamp.month == now.month);
    var income = 0.0;
    var expense = 0.0;
    for (final e in thisMonth) {
      if (e.type == MoneyEntryType.income) {
        income += e.amount;
      } else {
        expense += e.amount;
      }
    }
    return (income: income, expense: expense);
  }
}
