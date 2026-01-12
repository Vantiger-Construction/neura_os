import 'memory_models.dart';

/// Stores and retrieves memories
class MemoryStore {
  final Map<String, Memory> _memories = {};
  
  Future<void> store(Memory memory) async {
    _memories[memory.id] = memory;
  }
  
  Future<Memory?> retrieve(String id) async {
    return _memories[id];
  }
  
  Future<List<Memory>> retrieveAll({int limit = 100}) async {
    final memories = _memories.values.toList();
    memories.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return memories.take(limit).toList();
  }
  
  Future<List<Memory>> search(String query, {int limit = 10}) async {
    final results = _memories.values
        .where((m) => m.content.toLowerCase().contains(query.toLowerCase()))
        .toList();
    results.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return results.take(limit).toList();
  }
  
  Future<void> delete(String id) async {
    _memories.remove(id);
  }
  
  Future<void> clear() async {
    _memories.clear();
  }
  
  int get count => _memories.length;
}
