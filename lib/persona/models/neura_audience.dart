enum NeuraAudience {
  adult,
  teen,
  child,
}

extension NeuraAudienceLabel on NeuraAudience {
  String get label {
    switch (this) {
      case NeuraAudience.adult:
        return 'adult';
      case NeuraAudience.teen:
        return 'teen';
      case NeuraAudience.child:
        return 'child';
    }
  }
}
