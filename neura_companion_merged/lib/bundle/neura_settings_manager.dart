import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NeuraSettingsManager with ChangeNotifier {
  String _voice = 'gentle';
  bool _isVoiceEnabled = true;
  bool _quietMode = false;

  String get voice => _voice;
  bool get isVoiceEnabled => _isVoiceEnabled;
  bool get quietMode => _quietMode;

  Future<void> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _voice = prefs.getString('neura_voice') ?? 'gentle';
    _isVoiceEnabled = prefs.getBool('neura_voice_enabled') ?? true;
    _quietMode = prefs.getBool('neura_quiet_mode') ?? false;
    notifyListeners();
  }

  Future<void> setVoice(String voice) async {
    _voice = voice;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('neura_voice', voice);
    notifyListeners();
  }

  Future<void> toggleVoice(bool enabled) async {
    _isVoiceEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('neura_voice_enabled', enabled);
    notifyListeners();
  }

  Future<void> toggleQuietMode(bool enabled) async {
    _quietMode = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('neura_quiet_mode', enabled);
    notifyListeners();
  }
}