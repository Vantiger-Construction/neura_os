
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SuggestionFeedback {
  final String suggestionType;
  final int rating; // -1, 0, +1

  SuggestionFeedback({
    required this.suggestionType,
    required this.rating,
  });

  Map<String, dynamic> toJson() => {
        'suggestionType': suggestionType,
        'rating': rating,
      };

  factory SuggestionFeedback.fromJson(Map<String, dynamic> json) {
    return SuggestionFeedback(
      suggestionType: json['suggestionType'] as String,
      rating: (json['rating'] as num).toInt(),
    );
  }
}

class FeedbackService {
  FeedbackService._();

  static final FeedbackService instance = FeedbackService._();

  static const _storageKey = 'neura_suggestion_feedback';

  List<SuggestionFeedback> _cache = [];

  Future<void> _loadIfNeeded() async {
    if (_cache.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) {
      _cache = [];
      return;
    }
    final list = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    _cache = list.map(SuggestionFeedback.fromJson).toList();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    final data = jsonEncode(_cache.map((f) => f.toJson()).toList());
    await prefs.setString(_storageKey, data);
  }

  Future<void> addFeedback(String suggestionType, int rating) async {
    await _loadIfNeeded();
    _cache.add(SuggestionFeedback(
      suggestionType: suggestionType,
      rating: rating,
    ));
    await _save();
  }

  Future<double> preferenceScore(String suggestionType) async {
    await _loadIfNeeded();
    final list =
        _cache.where((f) => f.suggestionType == suggestionType).toList();
    if (list.isEmpty) return 0;
    final sum = list.fold<int>(0, (acc, f) => acc + f.rating);
    return sum / (list.length * 1.0);
  }
}
