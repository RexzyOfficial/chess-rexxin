import 'package:flutter/material.dart';

/// Label kualitas langkah berdasarkan centipawn loss (CPL).
enum MoveQuality {
  best('Best', Color(0xFF2E9E4F), Colors.white),
  excellent('Excellent', Color(0xFF8BC34A), Colors.black),
  good('Good', Color(0xFF3D8FE0), Colors.white),
  inaccuracy('Inaccuracy', Color(0xFFF2C500), Colors.black),
  mistake('Mistake', Color(0xFFF08A24), Colors.black),
  blunder('Blunder', Color(0xFFD7302F), Colors.white);

  const MoveQuality(this.label, this.color, this.onColor);

  final String label;
  final Color color;
  final Color onColor;

  /// 0-10 Best, 11-30 Excellent, 31-70 Good, 71-150 Inaccuracy,
  /// 151-300 Mistake, >300 Blunder.
  static MoveQuality fromCpl(int cpl) {
    if (cpl <= 10) return MoveQuality.best;
    if (cpl <= 30) return MoveQuality.excellent;
    if (cpl <= 70) return MoveQuality.good;
    if (cpl <= 150) return MoveQuality.inaccuracy;
    if (cpl <= 300) return MoveQuality.mistake;
    return MoveQuality.blunder;
  }
}
