import 'dart:async';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../engine/stockfish_service.dart';
import '../engine/uci.dart';
import 'game_line.dart';
import 'move_quality.dart';

enum AnalysisStatus { idle, running, done, cancelled, error }

class PositionAnalysis {
  const PositionAnalysis({
    required this.score,
    required this.depth,
    this.bestMove,
  });

  /// Dari sudut pandang pihak yang jalan pada posisi tersebut.
  final Score score;
  final int depth;

  /// Best move dalam format UCI, null untuk posisi game over.
  final String? bestMove;
}

class MoveReview {
  const MoveReview({required this.cpl, required this.quality});

  final int cpl;
  final MoveQuality quality;
}

/// Menganalisis seluruh posisi sebuah [GameLine] dengan Stockfish
/// (depth 20, movetime 5000 ms per posisi) lalu menghitung CPL tiap langkah.
class AnalysisController extends ChangeNotifier {
  AnalysisController(this.line)
      : _analyses = List<PositionAnalysis?>.filled(line.positions.length, null),
        _reviews = List<MoveReview?>.filled(line.length, null);

  static const int _clampCp = 1000;

  final GameLine line;
  final StockfishService _engine = StockfishService.instance;
  final List<PositionAnalysis?> _analyses;
  final List<MoveReview?> _reviews;

  AnalysisStatus status = AnalysisStatus.idle;
  String? errorMessage;
  int doneCount = 0;

  /// 0 = posisi awal, k = posisi setelah langkah ke-k.
  int selectedIndex = 0;

  bool _cancelRequested = false;
  bool _disposed = false;

  double get progress =>
      line.positions.isEmpty ? 0 : doneCount / line.positions.length;

  int get progressMove => math.max(1, math.min(line.length, doneCount));

  PositionAnalysis? analysisAt(int index) => _analyses[index];

  MoveReview? reviewOfPly(int ply) =>
      (ply >= 1 && ply <= _reviews.length) ? _reviews[ply - 1] : null;

  /// Best move (UCI) untuk pihak yang jalan pada posisi [index].
  /// Null bila belum dianalisis atau posisi sudah game over.
  String? bestMoveAt(int index) {
    if (line.positions[index].isGameOver) return null;
    return _analyses[index]?.bestMove;
  }

  void select(int index) {
    final int i = math.max(0, math.min(line.length, index));
    if (i == selectedIndex) return;
    selectedIndex = i;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> run() async {
    if (status == AnalysisStatus.running) return;

    _cancelRequested = false;
    status = AnalysisStatus.running;
    errorMessage = null;
    doneCount = 0;
    _analyses.fillRange(0, _analyses.length, null);
    _reviews.fillRange(0, _reviews.length, null);
    _notify();

    final bool ok = await _engine.ensureStarted();
    if (_disposed) return;
    if (!ok) {
      _fail('Stockfish gagal dijalankan. ${_engine.lastError ?? ''}'.trim());
      return;
    }
    await _engine.newGame();
    if (_disposed) return;

    for (int i = 0; i < line.positions.length; i++) {
      if (_cancelRequested || _disposed) break;

      final Position pos = line.positions[i];
      final PositionAnalysis analysis;

      if (pos.isGameOver) {
        analysis = PositionAnalysis(
          score: pos.isCheckmate ? const Score.mate(0) : const Score.cp(0),
          depth: 0,
        );
      } else {
        final EngineResult? result = await _engine.analyze(pos.fen);
        if (_disposed) return;
        if (_cancelRequested) break;
        if (result == null) {
          _fail('Analisis terhenti. Tekan tombol untuk mengulang.');
          return;
        }
        analysis = PositionAnalysis(
          score: result.score,
          depth: result.depth,
          bestMove: result.bestMove,
        );
      }

      _analyses[i] = analysis;
      doneCount = i + 1;
      _computeReview(i);
      _notify();
    }

    if (_disposed) return;
    status =
        _cancelRequested ? AnalysisStatus.cancelled : AnalysisStatus.done;
    _notify();
  }

  /// CPL = eval terbaik sebelum langkah - eval setelah langkah,
  /// keduanya dari sudut pandang pemain yang melangkah.
  void _computeReview(int index) {
    if (index < 1) return;
    final PositionAnalysis? before = _analyses[index - 1];
    final PositionAnalysis? after = _analyses[index];
    if (before == null || after == null) return;

    final int bestCp = _limit(before.score.asCp);
    // Posisi sesudah langkah dinilai dari sisi lawan -> dibalik.
    final int playedCp = _limit(-after.score.asCp);
    final int cpl = math.max(0, bestCp - playedCp);

    _reviews[index - 1] =
        MoveReview(cpl: cpl, quality: MoveQuality.fromCpl(cpl));
  }

  int _limit(int cp) => math.max(-_clampCp, math.min(_clampCp, cp));

  void _fail(String message) {
    status = AnalysisStatus.error;
    errorMessage = message;
    _notify();
    unawaited(_engine.cancel());
  }

  Future<void> cancel() async {
    if (status != AnalysisStatus.running) return;
    _cancelRequested = true;
    await _engine.cancel();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelRequested = true;
    // Keluar dari layar analisis: hentikan pencarian dan matikan engine.
    unawaited(_engine.shutdown());
    super.dispose();
  }
}
