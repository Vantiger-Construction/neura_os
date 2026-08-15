import 'dart:math';
import 'support_models.dart';
import '../../startup/neura_prefs_cache.dart';

class SupportStore {
  SupportStore._();
  static final SupportStore instance = SupportStore._();

  static const _key = 'neura.support.trusted_contacts.v1';

  String _id() =>
      'c_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1 << 32)}';

  Future<List<TrustedContact>> getAll() async {
    final sp = NeuraPrefsCache.prefs;
    return decodeContacts(sp.getString(_key) ?? '');
  }

  Future<void> _write(List<TrustedContact> list) async {
    final sp = NeuraPrefsCache.prefs;
    await sp.setString(_key, encodeContacts(list));
  }

  Future<void> add(
      {required String name, required String phone, String note = ''}) async {
    final list = await getAll();
    list.add(TrustedContact(
        id: _id(), name: name.trim(), phone: phone.trim(), note: note.trim()));
    await _write(list);
  }

  Future<void> delete(String id) async {
    final list = await getAll();
    list.removeWhere((c) => c.id == id);
    await _write(list);
  }

  Future<void> wipe() async {
    final sp = NeuraPrefsCache.prefs;
    await sp.remove(_key);
  }
}
