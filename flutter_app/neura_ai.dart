class Neura {
  static void respondToHeartRate(int bpm) {
    if (bpm > 100) {
      print("😟 Neura: Let's slow down. Try a deep breath.");
    } else if (bpm < 60) {
      print("🧘 Neura: Calm and steady... you're doing great.");
    } else {
      print("😊 Neura: Looking good! Keep it up.");
    }
  }
}