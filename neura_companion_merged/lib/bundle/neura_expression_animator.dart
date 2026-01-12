import 'package:flutter/material.dart';

class NeuraExpressionAnimator extends ChangeNotifier {
  String currentExpression = "default";
  int evolutionLevel = 1;

  List<String> expressions = [
    "default",
    "blink",
    "smile",
    "squint",
    "sparkle",
    "wink",
    "surprised",
  ];

  List<String> accessories = [];

  void evolve(int daysActive) {
    evolutionLevel = (daysActive ~/ 7).clamp(1, 5); // evolve every week
    _updateExpressionByLevel();
    _unlockAccessories();
    notifyListeners();
  }

  void _updateExpressionByLevel() {
    switch (evolutionLevel) {
      case 1:
        currentExpression = "smile";
        break;
      case 2:
        currentExpression = "blink";
        break;
      case 3:
        currentExpression = "sparkle";
        break;
      case 4:
        currentExpression = "wink";
        break;
      case 5:
        currentExpression = "surprised";
        break;
      default:
        currentExpression = "default";
    }
  }

  void _unlockAccessories() {
    accessories.clear();
    if (evolutionLevel >= 2) accessories.add("glow ring");
    if (evolutionLevel >= 3) accessories.add("tiny headphones");
    if (evolutionLevel >= 4) accessories.add("holo scarf");
    if (evolutionLevel >= 5) accessories.add("star crown");
  }

  String getExpressionLabel() => currentExpression;
  List<String> getAccessories() => accessories;
}