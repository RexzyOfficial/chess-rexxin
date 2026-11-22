import 'dart:async';
import 'dart:math' as math;

import 'package:dartchess/dartchess.dart';
import 'package:flutter/foundation.dart';

import '../engine/stockfish_service.dart';
import '../engine/uci.dart';
import 'analysis_models.dart';
import 'game_line.dart';
import 'move_classifier.dart';
import 'opening_book.dart';

export 'analysis_models.dart';

enum AnalysisStatus { idle, running, done, cancelled, error }

/// Menganalisis seluruh posisi sebuah [GameLine] dengan Stockfish
/// (depth 22, MultiPV 2, tanpa batas waktu) lalu menghitung CPL dan label
/// kualitas tiap langkah.
class AnalysisController extends ChangeNotifier {
  AnalysisController(this.line)
      : _analyses = List<PositionAnalysis?>.filled(line.positions.length, null),
        _reviews = List<MoveReview?>.filled(line.length, null);

  final GameLine line;
  final StockfishService _engine = StockfishService.instance;
  final List<PositionAnalysis?> _analyses;
  final List<MoveReview?> _reviews;

  AnalysisStatus status = AnalysisStatus.idle;
  String? errorMessage;
  int doneCount = 0;

  /// Depth terakhir yang dicapai pada posisi yang sedang dianalisis (0 = belum mulai).
  int currentDepth = 0;

  /// 0 = posisi awal, k = posisi setelah langkah ke-k.
  int selectedIndex = 0;

  bool _cancelRequested = false;
  bool _disposed = false;

  double get progress {
    final int total = line.positions.length;
    if (total == 0) return 0;
    final double inner = status == AnalysisStatus.running
        ? math.min(currentDepth, StockfishService.analysisDepth) /
            StockfishService.analysisDepth
        : 0;
    return math.min(1.0, (doneCount + inner) / total);
  }

  PositionAnalysis? analysisAt(int index) => _analyses[index];

  MoveReview? reviewOfPly(int ply) =>
      (ply >= 1 && ply <= _reviews.length) ? _reviews[ply - 1] : null;

  /// Best move MultiPV 1 (UCI) untuk pihak yang jalan pada posisi [index].
  /// Null bila belum dianalisis atau posisi sudah game over.
  String? bestMoveAt(int index) {
    if (line.positions[index].isGameOver) return null;
    return _analyses[index]?.bestMove;
  }

  /// Teks alternatif MultiPV 2, misalnya "Nf3 (+0.25)". Null bila tidak ada.
  String? alternativeLabelAt(int index) {
    final Position pos = line.positions[index];
    if (pos.isGameOver) return null;
    final PositionAnalysis? a = _analyses[index];
    final String? uci = a?.altMove;
    final Score? score = a?.altScore;
    if (a == null || uci == null || score == null) return null;
    try {
      final Move move = pos.normalizeMove(NormalMove.fromUci(uci));
      final (_, san) = pos.makeSan(move);
      return '$san (${formatEval(score, pos.turn)})';
    } catch (_) {
      return null;
    }
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

  void _onDepth(int depth) {
    if (_disposed || _cancelRequested) return;
    currentDepth = depth;
    _notify();
  }

  Future<void> run() async {
    if (status == AnalysisStatus.running) return;

    _cancelRequested = false;
    status = AnalysisStatus.running;
    errorMessage = null;
    doneCount = 0;
    currentDepth = 0;
    _analyses.fillRange(0, _analyses.length, null);
    _reviews.fillRange(0, _reviews.length, null);
    _notify();

    // Buku opening dimuat paralel dengan start engine (tidak pernah melempar).
    final Future<void> bookFuture = OpeningBook.instance.ensureLoaded();

    final bool ok = await _engine.ensureStarted();
    if (_disposed) return;
    if (!ok) {
      _fail('Stockfish gagal dijalankan. ${_engine.lastError ?? ''}'.trim());
      return;
    }
    await _engine.newGame();
    if (_disposed) return;
    await bookFuture;
    if (_disposed) return;

    for (int i = 0; i < line.positions.length; i++) {
      if (_cancelRequested || _disposed) break;

      final Position pos = line.positions[i];
      final PositionAnalysis analysis;
      currentDepth = 0;

      if (pos.isGameOver) {
        // Posisi akhir tidak dikirim ke engine.
        analysis = PositionAnalysis(
          score: pos.isCheckmate ? const Score.mate(0) : const Score.cp(0),
          depth: 0,
        );
      } else {
        final EngineResult? result =
            await _engine.analyze(pos.fen, onDepth: _onDepth);
        if (_disposed) return;
        if (_cancelRequested) break;
        if (result == null) {
          _fail('Analisis terhenti. Tekan tombol untuk mengulang.');
          return;
        }
        analysis = PositionAnalysis(
          score: result.primary.score,
          depth: result.primary.depth,
          bestMove: result.bestMove,
          pv: result.primary.pv,
          altScore: result.alternative?.score,
          altMove: result.alternative?.move,
        );
      }

      _analyses[i] = analysis;
      doneCount = i + 1;
      currentDepth = 0;
      _computeReview(i);
      _notify();
    }

    if (_disposed) return;
    currentDepth = 0;
    status =
        _cancelRequested ? AnalysisStatus.cancelled : AnalysisStatus.done;
    _notify();
  }

  /// Menghitung CPL dan label untuk langkah yang menuju posisi [index].
  void _computeReview(int index) {
    if (index < 1) return;
    final PositionAnalysis? before = _analyses[index - 1];
    final PositionAnalysis? after = _analyses[index];
    if (before == null || after == null) return;

    _reviews[index - 1] = reviewMove(
      before: line.positions[index - 1],
      afterPosition: line.positions[index],
      move: line.moves[index - 1],
      beforeAnalysis: before,
      afterAnalysis: after,
      inBook: OpeningBook.instance.contains(line.positions[index]),
    );
  }

  void _fail(String message) {
    currentDepth = 0;
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
