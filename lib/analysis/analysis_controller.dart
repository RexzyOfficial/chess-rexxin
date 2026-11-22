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

/// quick  = tahap 1: semua posisi (depth 16, posisi buku depth 12).
/// verify = tahap 2: hanya posisi/langkah rumit pada depth 18.
enum AnalysisStage { quick, verify }

/// Menganalisis seluruh posisi sebuah [GameLine] dengan Stockfish (MultiPV 2,
/// tanpa batas waktu) dalam dua tahap, lalu menghitung CPL dan label kualitas.
class AnalysisController extends ChangeNotifier {
  AnalysisController(this.line)
      : _analyses = List<PositionAnalysis?>.filled(line.positions.length, null),
        _reviews = List<MoveReview?>.filled(line.length, null),
        _deep = List<bool>.filled(line.positions.length, false);

  final GameLine line;
  final StockfishService _engine = StockfishService.instance;
  final List<PositionAnalysis?> _analyses;
  final List<MoveReview?> _reviews;

  /// _deep[i] = posisi i sudah dianalisis pada depth penuh (>= deepDepth).
  final List<bool> _deep;

  /// Nomor langkah (1-based) yang labelnya masih menunggu verifikasi.
  final Set<int> _pending = <int>{};
  bool _planned = false;

  AnalysisStatus status = AnalysisStatus.idle;
  AnalysisStage stage = AnalysisStage.quick;
  String? errorMessage;

  /// Tahap 1: jumlah posisi yang selesai (juga = indeks posisi yang sedang dianalisis).
  int doneCount = 0;

  /// Tahap 2: posisi yang sudah diverifikasi dari total yang direncanakan.
  int deepDone = 0;
  int deepTotal = 0;

  /// Depth terakhir yang dicapai pada pencarian saat ini (0 = belum mulai).
  int currentDepth = 0;

  /// Depth tujuan pencarian saat ini (12, 16, atau 18).
  int targetDepth = 0;

  /// 0 = posisi awal, k = posisi setelah langkah ke-k.
  int selectedIndex = 0;

  bool _cancelRequested = false;
  bool _disposed = false;

  double get progress {
    final double inner = (status == AnalysisStatus.running && targetDepth > 0)
        ? math.min(currentDepth, targetDepth) / targetDepth
        : 0;
    if (stage == AnalysisStage.verify) {
      if (deepTotal == 0) return 1;
      return math.min(1.0, (deepDone + inner) / deepTotal);
    }
    final int total = line.positions.length;
    if (total == 0) return 0;
    return math.min(1.0, (doneCount + inner) / total);
  }

  PositionAnalysis? analysisAt(int index) => _analyses[index];

  MoveReview? reviewOfPly(int ply) =>
      (ply >= 1 && ply <= _reviews.length) ? _reviews[ply - 1] : null;

  /// False selama label langkah [ply] masih sementara (belum diverifikasi).
  bool isReviewFinal(int ply) {
    if (!_planned) return false;
    return !_pending.contains(ply);
  }

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

  /// Depth tahap 1: posisi buku opening interior pakai depth rendah.
  /// Posisi buku TERAKHIR tetap depth penuh tahap 1 karena menjadi patokan
  /// untuk langkah pertama yang keluar dari buku.
  int _quickDepthFor(int i) {
    final OpeningBook book = OpeningBook.instance;
    if (i + 1 >= line.positions.length) return StockfishService.quickDepth;
    if (!book.isBookPosition(line.positions[i])) {
      return StockfishService.quickDepth;
    }
    return book.isBookPosition(line.positions[i + 1])
        ? StockfishService.bookDepth
        : StockfishService.quickDepth;
  }

  Future<PositionAnalysis?> _search(Position pos, int depth) async {
    final EngineResult? r =
        await _engine.analyze(pos.fen, depth: depth, onDepth: _onDepth);
    if (r == null) return null;
    return PositionAnalysis(
      score: r.primary.score,
      depth: depth,
      bestMove: r.bestMove,
      pv: r.primary.pv,
      altScore: r.alternative?.score,
      altMove: r.alternative?.move,
    );
  }

  Future<void> run() async {
    if (status == AnalysisStatus.running) return;

    _cancelRequested = false;
    status = AnalysisStatus.running;
    stage = AnalysisStage.quick;
    errorMessage = null;
    doneCount = 0;
    deepDone = 0;
    deepTotal = 0;
    currentDepth = 0;
    targetDepth = 0;
    _planned = false;
    _pending.clear();
    _analyses.fillRange(0, _analyses.length, null);
    _reviews.fillRange(0, _reviews.length, null);
    _deep.fillRange(0, _deep.length, false);
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

    // ---- Tahap 1: semua posisi ----
    for (int i = 0; i < line.positions.length; i++) {
      if (_cancelRequested || _disposed) break;

      final Position pos = line.positions[i];
      currentDepth = 0;

      if (pos.isGameOver) {
        // Posisi akhir tidak dikirim ke engine.
        _analyses[i] = PositionAnalysis(
          score: pos.isCheckmate ? const Score.mate(0) : const Score.cp(0),
          depth: StockfishService.deepDepth,
        );
        _deep[i] = true;
      } else {
        final int depth = _quickDepthFor(i);
        targetDepth = depth;
        final PositionAnalysis? analysis = await _search(pos, depth);
        if (_disposed) return;
        if (_cancelRequested) break;
        if (analysis == null) {
          _fail('Analisis terhenti. Tekan tombol untuk mengulang.');
          return;
        }
        _analyses[i] = analysis;
        _deep[i] = depth >= StockfishService.deepDepth;
      }

      doneCount = i + 1;
      currentDepth = 0;
      _computeReview(i);
      _notify();
    }

    if (_disposed) return;
    if (_cancelRequested) {
      _finish(AnalysisStatus.cancelled);
      return;
    }

    // ---- Tahap 2: verifikasi posisi/langkah rumit pada depth 18 ----
    final List<int> order = _planVerification();
    stage = AnalysisStage.verify;
    deepTotal = order.length;
    deepDone = 0;
    _planned = true;
    _notify();

    for (final int idx in order) {
      if (_cancelRequested || _disposed) break;

      currentDepth = 0;
      targetDepth = StockfishService.deepDepth;
      final PositionAnalysis? analysis =
          await _search(line.positions[idx], StockfishService.deepDepth);
      if (_disposed) return;
      if (_cancelRequested) break;
      if (analysis == null) {
        _fail('Verifikasi terhenti. Hasil tahap 1 tetap tersimpan.');
        return;
      }

      _analyses[idx] = analysis;
      _deep[idx] = true;
      deepDone++;
      currentDepth = 0;
      _computeReview(idx);
      _computeReview(idx + 1);
      _settlePending(idx);
      _notify();
    }

    if (_disposed) return;
    _finish(_cancelRequested ? AnalysisStatus.cancelled : AnalysisStatus.done);
  }

  void _finish(AnalysisStatus result) {
    currentDepth = 0;
    status = result;
    _notify();
  }

  /// Memilih posisi yang perlu dianalisis ulang pada depth 18, diurutkan dari
  /// prioritas tertinggi. Mengisi [_pending] dengan langkah yang menunggu.
  List<int> _planVerification() {
    final Map<int, int> priority = <int, int>{};

    for (int ply = 1; ply <= line.length; ply++) {
      final MoveReview? review = _reviews[ply - 1];
      final PositionAnalysis? b = _analyses[ply - 1];
      final PositionAnalysis? a = _analyses[ply];
      if (review == null || b == null || a == null) continue;
      if (_deep[ply - 1] && _deep[ply]) continue; // sudah dianalisis dalam

      final int? p = verificationPriority(
        before: line.positions[ply - 1],
        afterPosition: line.positions[ply],
        b: b,
        a: a,
        review: review,
      );
      if (p == null) continue;

      _pending.add(ply);
      for (final int idx in <int>[ply - 1, ply]) {
        if (_deep[idx]) continue;
        priority[idx] = math.max(priority[idx] ?? -1, p);
      }
    }

    final List<int> order = priority.keys.toList()
      ..sort((int x, int y) => priority[y]!.compareTo(priority[x]!));
    return order;
  }

  /// Langkah dianggap final bila kedua posisinya sudah dianalisis depth penuh.
  void _settlePending(int idx) {
    for (final int ply in <int>[idx, idx + 1]) {
      if (ply >= 1 &&
          ply < _analyses.length &&
          _pending.contains(ply) &&
          _deep[ply - 1] &&
          _deep[ply]) {
        _pending.remove(ply);
      }
    }
  }

  /// Menghitung CPL dan label untuk langkah yang menuju posisi [index].
  void _computeReview(int index) {
    if (index < 1 || index >= _analyses.length) return;
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
