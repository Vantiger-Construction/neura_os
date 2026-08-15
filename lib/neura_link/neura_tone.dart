import 'package:flutter/material.dart';

enum NeuraTone { calm, warm, focused, hopeful, alert, neutral }

extension NeuraToneStyle on NeuraTone {
  Color get accent => switch (this) {
        NeuraTone.calm => const Color(0xFF5BC0EB),
        NeuraTone.warm => const Color(0xFFFFA45B),
        NeuraTone.focused => const Color(0xFF8C7AE6),
        NeuraTone.hopeful => const Color(0xFF55D6BE),
        NeuraTone.alert => const Color(0xFFFF5D73),
        NeuraTone.neutral => const Color(0xFF9AA4B2),
      };
}

class ToneController extends ValueNotifier<NeuraTone> {
  ToneController() : super(NeuraTone.neutral);
  void setFromWire(String? name) {
    value = NeuraTone.values.firstWhere(
      (tone) => tone.name == name,
      orElse: () => NeuraTone.neutral,
    );
  }
}
