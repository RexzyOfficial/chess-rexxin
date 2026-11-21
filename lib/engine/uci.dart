import 'package:dartchess/dartchess.dart';

/// Skor Stockfish dari sudut pandang pihak yang sedang jalan (standar UCI).
class Score {
  const Score.cp(int value)
      : cp = value,
        mate = null;
  const Score.mate(int value)
      : mate = value,
        cp = null;

  final int? cp;
  final int? mate;

  static const int mateCp = 10000;

  /// Skor dalam centipawn; skor mate diubah menjadi angka besar.
  int get asCp {
    final int? m = mate;
    if (m == null) return cp!;
    if (m > 0) return mateCp - m;
    if (m < 0) return -mateCp - m;
    return -mateCp; // mate 0 = pihak yang jalan sudah skakmat
  }
}

class InfoLine {
  const InfoLine({required this.depth, required this.score, required this.pv});

  final int depth;
  final Score score;
  final List<String> pv;
}

class EngineResult {
  const EngineResult({
    required this.score,
    required this.depth,
    required this.pv,
    required this.bestMove,
  });

  final Score score;
  final int depth;
  final List<String> pv;
  final String? bestMove;
}

/// Parse baris `info depth .. score cp|mate .. pv ..`.
/// Mengembalikan null untuk baris lain, bound (lower/upper), atau multipv > 1.
InfoLine? parseInfoLine(String line) {
  if (!line.startsWith('info ') || line.startsWith('info string')) return null;

  final List<String> t = line.split(' ');
  int? depth;
  Score? score;
  List<String> pv = <String>[];
  bool bounded = false;
  int multipv = 1;

  int i = 1;
  while (i < t.length) {
    switch (t[i]) {
      case 'depth':
        if (i + 1 < t.length) depth = int.tryParse(t[i + 1]);
        i += 2;
      case 'multipv':
        if (i + 1 < t.length) multipv = int.tryParse(t[i + 1]) ?? 1;
        i += 2;
      case 'score':
        if (i + 2 < t.length) {
          final int? v = int.tryParse(t[i + 2]);
          if (v != null) {
            if (t[i + 1] == 'cp') {
              score = Score.cp(v);
            } else if (t[i + 1] == 'mate') {
              score = Score.mate(v);
            }
          }
        }
        i += 3;
      case 'lowerbound' || 'upperbound':
        bounded = true;
        i += 1;
      case 'pv':
        pv = t.sublist(i + 1);
        i = t.length;
      default:
        i += 1;
    }
  }

  if (depth == null || score == null || bounded || multipv != 1) return null;
  return InfoLine(depth: depth, score: score, pv: pv);
}

/// Evaluasi singkat dari sudut pandang Putih: "+0.35", "-1.20", "#3", "-#2".
String formatEval(Score score, Side turn) {
  final bool whiteToMove = turn == Side.white;
  final int? m = score.mate;
  if (m != null) {
    if (m == 0) return whiteToMove ? '0-1' : '1-0';
    final int whiteMate = whiteToMove ? m : -m;
    return whiteMate > 0 ? '#$whiteMate' : '-#${-whiteMate}';
  }
  final int cpWhite = whiteToMove ? score.cp! : -score.cp!;
  final String sign = cpWhite > 0 ? '+' : (cpWhite < 0 ? '-' : '');
  return '$sign${(cpWhite.abs() / 100).toStringAsFixed(2)}';
}
