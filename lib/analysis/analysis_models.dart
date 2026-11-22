import '../engine/uci.dart';
import 'move_quality.dart';

class PositionAnalysis {
  const PositionAnalysis({
    required this.score,
    required this.depth,
    this.bestMove,
    this.pv = const <String>[],
    this.altScore,
    this.altMove,
  });

  /// MultiPV 1: dari sudut pandang pihak yang jalan pada posisi tersebut.
  final Score score;
  final int depth;

  /// Best move MultiPV 1 (UCI), null untuk posisi game over.
  final String? bestMove;

  /// Variasi utama MultiPV 1 (UCI), dipakai untuk menilai material/taktik.
  final List<String> pv;

  /// MultiPV 2: alternatif terkuat berikutnya (null bila hanya ada satu langkah legal).
  final Score? altScore;
  final String? altMove;
}

class MoveReview {
  const MoveReview({required this.cpl, required this.quality});

  final int cpl;
  final MoveQuality quality;
}
