import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Kid-friendly gratitude journaling screen.
///
/// Children type one thing they are grateful for and earn a star.
/// Entries are persisted to SharedPreferences and displayed in a scrollable list.
class GratitudeStarsScreen extends StatefulWidget {
  const GratitudeStarsScreen({super.key});

  @override
  State<GratitudeStarsScreen> createState() => _GratitudeStarsScreenState();
}

class _GratitudeStarsScreenState extends State<GratitudeStarsScreen> {
  static const String _prefKey = 'kids_gratitude_stars_v1';

  final TextEditingController _textCtrl = TextEditingController();
  final List<_GratitudeEntry> _entries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefKey);
    if (raw != null) {
      try {
        final list = json.decode(raw) as List<dynamic>;
        for (final item in list) {
          if (item is Map) {
            _entries.add(
              _GratitudeEntry.fromMap(Map<String, dynamic>.from(item)),
            );
          }
        }
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefKey,
      json.encode(_entries.map((e) => e.toMap()).toList()),
    );
  }

  void _addEntry() {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) return;

    final entry = _GratitudeEntry(text: text, createdAt: DateTime.now());
    setState(() {
      _entries.insert(0, entry);
      _textCtrl.clear();
    });
    _save();

    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        title: const Text(
          '⭐ Amazing!',
          style: TextStyle(color: Colors.amber, fontSize: 22),
        ),
        content: Text(
          '"$text"\n\nYou earned a star! Great job!',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Thanks!', style: TextStyle(color: Colors.amber)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gratitude Stars ⭐'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      backgroundColor: const Color(0xFF1A1A2E),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Column(
                      children: [
                        const Text(
                          'What are you grateful for today?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Every grateful thought earns a ⭐',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${_entries.length} ⭐ collected',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textCtrl,
                            style: const TextStyle(color: Colors.white),
                            maxLength: 100,
                            decoration: InputDecoration(
                              hintText: 'e.g. My dog, the sun, my family…',
                              hintStyle: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                              ),
                              counterStyle: const TextStyle(
                                color: Colors.white70,
                              ),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.12),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onSubmitted: (_) => _addEntry(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: _addEntry,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade700,
                            shape: const CircleBorder(),
                            padding: const EdgeInsets.all(14),
                          ),
                          child: const Icon(Icons.star, color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _entries.isEmpty
                        ? Center(
                            child: Text(
                              'No stars yet!\nType something above to earn your first ⭐',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.75),
                                fontSize: 15,
                              ),
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                            itemCount: _entries.length,
                            itemBuilder: (ctx, i) {
                              final e = _entries[i];
                              return Card(
                                color: Colors.white.withValues(alpha: 0.12),
                                margin: const EdgeInsets.symmetric(vertical: 4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: ListTile(
                                  leading: const Text(
                                    '⭐',
                                    style: TextStyle(fontSize: 22),
                                  ),
                                  title: Text(
                                    e.text,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    _formatDate(e.createdAt),
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 11,
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _GratitudeEntry {
  final String text;
  final DateTime createdAt;

  const _GratitudeEntry({required this.text, required this.createdAt});

  Map<String, dynamic> toMap() => {
        'text': text,
        'createdAt': createdAt.toIso8601String(),
      };

  factory _GratitudeEntry.fromMap(Map<String, dynamic> m) => _GratitudeEntry(
        text: m['text'] as String? ?? '',
        createdAt: DateTime.tryParse(m['createdAt'] as String? ?? '') ??
            DateTime.now(),
      );
}
