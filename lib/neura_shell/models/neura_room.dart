import 'package:flutter/material.dart';

/// The "where am I?" layer of Neura OS.
///
/// Think of these as themed rooms/realms that tint the whole UI.
class NeuraRoom {
  final String id;
  final String title;
  final IconData icon;
  final List<Color> gradient;
  final String? ambientSoundAsset;

  const NeuraRoom({
    required this.id,
    required this.title,
    required this.icon,
    required this.gradient,
    this.ambientSoundAsset,
  });

  // Built-in rooms. Add more as your OS grows.
  static const penthouse = NeuraRoom(
    id: 'penthouse',
    title: 'Penthouse',
    icon: Icons.home_outlined,
    gradient: [Color(0xFF0B1020), Color(0xFF1A1F3A), Color(0xFF0E3B43)],
    ambientSoundAsset: 'assets/sounds/ambient_loop.mp3',
  );

  static const reflectionBay = NeuraRoom(
    id: 'reflection_bay',
    title: 'Reflection Bay',
    icon: Icons.waves_outlined,
    gradient: [Color(0xFF05121A), Color(0xFF0B2733), Color(0xFF1C4E6B)],
    ambientSoundAsset: 'assets/sounds/ocean.mp3',
  );

  static const joyLounge = NeuraRoom(
    id: 'joy_lounge',
    title: 'Joy Lounge',
    icon: Icons.emoji_emotions_outlined,
    gradient: [Color(0xFF1B0B2D), Color(0xFF3A155F), Color(0xFF0E3B43)],
    ambientSoundAsset: 'assets/sounds/ambient_loop.mp3',
  );

  static const moodDen = NeuraRoom(
    id: 'mood_den',
    title: 'Mood Den',
    icon: Icons.mood_outlined,
    gradient: [Color(0xFF0A0F1E), Color(0xFF1A1F3A), Color(0xFF3B2B4A)],
    ambientSoundAsset: 'assets/sounds/wind.mp3',
  );

  static const dreamAtrium = NeuraRoom(
    id: 'dream_atrium',
    title: 'Dream Atrium',
    icon: Icons.auto_awesome_outlined,
    gradient: [Color(0xFF0A0A1F), Color(0xFF1B1440), Color(0xFF3A1C5C)],
    ambientSoundAsset: 'assets/sounds/breathe.mp3',
  );

  static const legacyVault = NeuraRoom(
    id: 'legacy_vault',
    title: 'Legacy Vault',
    icon: Icons.lock_outline,
    gradient: [Color(0xFF070A10), Color(0xFF141A28), Color(0xFF0B2733)],
    ambientSoundAsset: 'assets/sounds/breathe.mp3',
  );

  static const List<NeuraRoom> all = [
    penthouse,
    reflectionBay,
    joyLounge,
    moodDen,
    dreamAtrium,
    legacyVault,
  ];

  static final Map<String, NeuraRoom> _byId = {
    for (final room in all) room.id: room,
  };

  static NeuraRoom fromId(String? id) => _byId[id] ?? penthouse;
}
