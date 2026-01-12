class EmotionSmoother {
  double smooth(double previous, double current, {double alpha = 0.85}) {
    return previous * alpha + current * (1 - alpha);
  }
}
