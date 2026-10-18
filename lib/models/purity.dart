/// Gold purities supported by the app.
enum Purity {
  k9(9, 375, 40),
  k14(14, 585, 60),
  k18(18, 750, 76),
  k20(20, 833, 84),
  k22(22, 916, 92),
  k24(24, 999, 100);

  const Purity(this.karat, this.fineness, this.percentOf24);

  final int karat;

  /// Hallmark fineness commonly stamped/printed for this purity.
  final int fineness;

  /// This purity's gold rate as a percentage of the 24K rate. Only the 24K
  /// rate is entered; every other rate is derived from it.
  final int percentOf24;

  String get label => '${karat}K';

  static Purity? fromKarat(int karat) {
    for (final p in Purity.values) {
      if (p.karat == karat) return p;
    }
    return null;
  }

  /// Maps a hallmark fineness number (585/750/916/995/999…) to a purity.
  static Purity? fromFineness(int fineness) {
    switch (fineness) {
      case 375:
        return Purity.k9;
      case 583:
      case 585:
        return Purity.k14;
      case 750:
        return Purity.k18;
      case 833:
        return Purity.k20;
      case 916:
        return Purity.k22;
      case 995:
      case 999:
        return Purity.k24;
    }
    return null;
  }

  static Purity? fromName(String? name) {
    for (final p in Purity.values) {
      if (p.name == name) return p;
    }
    return null;
  }
}
