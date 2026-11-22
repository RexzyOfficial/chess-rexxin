import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';

import '../engine/uci.dart';
import 'analysis_models.dart';
import 'move_quality.dart';

const int _clampCp = 1000;
const Map<String, int> _pieceValue = <String, int>{
  'p': 1,
  'n': 3,
  'b': 3,
  'r': 5,
  'q': 9,
};

int _limit(int cp) => math.max(-_clampCp, math.min(_clampCp, cp));

/// Selisih material [side] terhadap lawan (P=1, N=B=3, R=5, Q=9), dari FEN.
int _balance(Position pos, Side side) {
  final String board = pos.fen.split(' ').first;
  int white = 0;
  int black = 0;
  for (final int unit in board.codeUnits) {
    final String ch = String.fromCharCode(unit);
    final int? value = _pieceValue[ch.toLowerCase()];
    if (value == null) continue;
    if (ch == ch.toUpperCase()) {
      white += value;
    } else {
      black += value;
    }
  }
  return side == Side.white ? white - black : black - white;
}

/// Memainkan variasi [pv] dari [start] (maksimal [maxPlies] langkah) lalu
/// mengembalikan posisi pada panjang yang "tenang": setelah langkah lawan
/// bila [oddOnly] false (pemain jalan duluan), atau setelah langkah lawan
/// bila [oddOnly] true (lawan jalan duluan). Null bila tidak ada.
Position? _settled(
  Position start,
  List<String> pv, {
  required int maxPlies,
  required bool oddOnly,
}) {
  final List<Position> trail = <Position>[];
  Position pos = start;
  for (final String uci in pv) {
    if (trail.length >= maxPlies) break;
    try {
      final Move m = pos.normalizeMove(NormalMove.fromUci(uci));
      if (!pos.isLegal(m)) break;
      pos = pos.play(m);
      trail.add(pos);
    } catch (_) {
      break;
    }
  }
  for (int n = trail.length; n >= 1; n--) {
    if ((n % 2 == 1) == oddOnly) return trail[n - 1];
  }
  return null;
}

bool _isPlayedMove(Position pos, String? uci, Move played) {
  if (uci == null) return false;
  try {
    final Move m = pos.normalizeMove(NormalMove.fromUci(uci));
    return m is NormalMove &&
        played is NormalMove &&
        m.from == played.from &&
        m.to == played.to &&
        m.promotion == played.promotion;
  } catch (_) {
    return false;
  }
}

/// Nilai langkah pemain (sudut pandang pemain). Dasarnya eval setelah langkah;
/// MultiPV 2 dipakai untuk menguji kewajarannya.
int _playedValue(
  Position before,
  Move played,
  PositionAnalysis b,
  int bestCp,
  int afterCp,
) {
  final Score? altScore = b.altScore;
  final int? altCp = altScore == null ? null : _limit(altScore.asCp);

  final int value;
  if (_isPlayedMove(before, b.bestMove, played)) {
    value = afterCp;
  } else if (altCp != null && _isPlayedMove(before, b.altMove, played)) {
    value = ((afterCp + altCp) / 2).round();
  } else if (altCp != null) {
    value = math.min(afterCp, altCp);
  } else {
    value = afterCp;
  }
  return math.min(value, bestCp);
}

/// Keuntungan material pemain di garis terbaik sebelum langkah (null bila PV pendek).
int? _bestLineGain(Position before, PositionAnalysis b, Side mover) {
  final Position? end =
      _settled(before, b.pv, maxPlies: 8, oddOnly: false);
  if (end == null) return null;
  return _balance(end, mover) - _balance(before, mover);
}

/// Perubahan material pemain di garis setelah langkah pemain (null bila PV pendek).
int? _playedLineDelta(
  Position before,
  Position afterPosition,
  PositionAnalysis a,
  Side mover,
) {
  final Position? end =
      _settled(afterPosition, a.pv, maxPlies: 7, oddOnly: true);
  if (end == null) return null;
  return _balance(end, mover) - _balance(before, mover);
}

/// Miss: ada peluang taktis (mate atau menang >= 3 poin material) di garis
/// terbaik, tetapi langkah pemain tidak merealisasikannya.
bool _missedTactic({
  required Position before,
  required PositionAnalysis b,
  required PositionAnalysis a,
  required Side mover,
  required int playedDelta,
}) {
  final bool mateAvailable = b.score.mate != null && b.score.mate! > 0;
  final bool stillMating = a.score.mate != null && a.score.mate! <= 0;
  if (mateAvailable && !stillMating) return true;

  final int? gain = _bestLineGain(before, b, mover);
  if (gain == null || gain < 3) return false;
  return playedDelta <= gain - 2;
}

/// Brilliant: langkah terbaik/sangat dekat terbaik yang mengorbankan material
/// dan sulit ditemukan (alternatif MultiPV 2 jelas lebih buruk).
bool _isBrilliant({
  required PositionAnalysis b,
  required int bestCp,
  required int playedCp,
  required int cpl,
  required int? lineDelta,
}) {
  if (cpl > 10) return false;
  final Score? alt = b.altScore;
  if (alt == null) return false; // langkah terpaksa (hanya satu pilihan)
  if (bestCp - _limit(alt.asCp) < 50) return false; // mudah ditemukan
  if (playedCp < -20) return false; // posisi memburuk
  if (b.score.mate == null && bestCp >= 800) return false; // sudah menang telak
  if (lineDelta == null) return false;
  return lineDelta <= -2; // mengorbankan >= 2 poin material
}

/// Menghitung CPL dan label kualitas satu langkah.
///
/// Urutan: Blunder > Mistake > Miss > Inaccuracy, lalu (CPL <= 70)
/// Book > Brilliant > Best/Excellent/Good.
MoveReview reviewMove({
  required Position before,
  required Position afterPosition,
  required Move move,
  required PositionAnalysis beforeAnalysis,
  required PositionAnalysis afterAnalysis,
  required bool inBook,
}) {
  final Side mover = before.turn;

  // Eval dari sudut pandang pemain yang melangkah.
  final int bestCp = _limit(beforeAnalysis.score.asCp);
  // Posisi sesudah langkah dinilai dari sisi lawan -> dibalik.
  final int afterCp = _limit(-afterAnalysis.score.asCp);
  final int playedCp =
      _playedValue(before, move, beforeAnalysis, bestCp, afterCp);
  final int cpl = math.max(0, bestCp - playedCp);

  MoveQuality quality = MoveQuality.fromCpl(cpl);
  try {
    final int immediate =
        _balance(afterPosition, mover) - _balance(before, mover);
    final int? lineDelta =
        _playedLineDelta(before, afterPosition, afterAnalysis, mover);
    final int playedDelta = lineDelta ?? immediate;

    if (cpl > 300) {
      // Blunder: eval runtuh (tidak lagi unggul jelas) atau kehilangan material besar.
      quality = (playedCp < 200 || playedDelta <= -3)
          ? MoveQuality.blunder
          : MoveQuality.mistake;
    } else if (cpl > 150) {
      quality = MoveQuality.mistake;
    } else if (cpl > 70) {
      quality = _missedTactic(
        before: before,
        b: beforeAnalysis,
        a: afterAnalysis,
        mover: mover,
        playedDelta: playedDelta,
      )
          ? MoveQuality.miss
          : MoveQuality.inaccuracy;
    } else if (inBook) {
      quality = MoveQuality.book;
    } else if (_isBrilliant(
      b: beforeAnalysis,
      bestCp: bestCp,
      playedCp: playedCp,
      cpl: cpl,
      lineDelta: lineDelta,
    )) {
      quality = MoveQuality.brilliant;
    }
  } catch (_) {
    // Simulasi garis gagal: pakai label dasar dari CPL.
  }

  return MoveReview(cpl: cpl, quality: quality);
}

/// Seberapa perlu langkah ini diverifikasi ulang pada depth lebih tinggi
/// (tahap 2). Null = langkah biasa, tidak perlu. Makin besar = makin prioritas.
///
/// Dianggap rumit bila: CPL >= 40, Brilliant, ada mate, garis terbaik
/// memenangkan material (CPL >= 15), mirip pengorbanan (CPL <= 30), atau
/// posisi "only move" dan langkah pemain bukan yang terbaik (CPL >= 20).
int? verificationPriority({
  required Position before,
  required Position afterPosition,
  required PositionAnalysis b,
  required PositionAnalysis a,
  required MoveReview review,
}) {
  final Side mover = before.turn;
  int priority = -1;

  if (review.cpl >= 40) priority = math.max(priority, review.cpl);
  if (review.quality == MoveQuality.brilliant) {
    priority = math.max(priority, 1400);
  }
  if ((b.score.mate ?? 0) != 0 || (a.score.mate ?? 0) != 0) {
    priority = math.max(priority, 500);
  }

  try {
    final int? gain = _bestLineGain(before, b, mover);
    if (gain != null && gain >= 3 && review.cpl >= 15) {
      priority = math.max(priority, 200 + review.cpl);
    }

    final int? delta = _playedLineDelta(before, afterPosition, a, mover);
    if (delta != null && delta <= -2 && review.cpl <= 30) {
      priority = math.max(priority, 300);
    }

    final Score? alt = b.altScore;
    if (alt != null) {
      final int gap = _limit(b.score.asCp) - _limit(alt.asCp);
      if (gap >= 150 && review.cpl >= 20) {
        priority = math.max(priority, 150 + review.cpl);
      }
    }
  } catch (_) {
    // Abaikan: kriteria lain tetap berlaku.
  }

  return priority < 0 ? null : priority;
}
