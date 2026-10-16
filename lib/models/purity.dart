/// Gold purities supported by the app.
enum Purity {
  k14(14, 585),
  k18(18, 750),
  k22(22, 916),
  k24(24, 999);

  const Purity(this.karat, this.fineness);

  final int karat;

  /// Hallmark fineness commonly stamped/printed for this purity.
  final int fineness;

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
      case 583:
      case 585:
        return Purity.k14;
      case 750:
        return Purity.k18;
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
