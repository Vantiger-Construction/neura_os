enum VoiceStyle { calm, supportive, focused, playful }

class VoiceStyleResolver {
  static VoiceStyle fromEmotion(double energy, double stress) {
    if (stress > 0.6) return VoiceStyle.calm;
    if (energy < 0.3) return VoiceStyle.supportive;
    if (energy > 0.7) return VoiceStyle.playful;
    return VoiceStyle.focused;
  }
}
