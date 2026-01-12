enum NeuraAudience {
  adult,
  teen,
  family,
  child,
  kids,
}

extension NeuraAudienceExtension on NeuraAudience {
  String get label {
    switch (this) {
      case NeuraAudience.adult:
        return 'adult';
      case NeuraAudience.teen:
        return 'teen';
      case NeuraAudience.family:
        return 'family';
      case NeuraAudience.child:
        return 'child';
      case NeuraAudience.kids:
        return 'kids';
    }
  }

  static NeuraAudience fromLabel(String label) {
    switch (label) {
      case 'teen':
        return NeuraAudience.teen;
      case 'family':
        return NeuraAudience.family;
      case 'child':
        return NeuraAudience.child;
      case 'kids':
        return NeuraAudience.kids;
      case 'adult':
      default:
        return NeuraAudience.adult;
    }
  }
}