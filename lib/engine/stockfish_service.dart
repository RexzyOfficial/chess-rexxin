import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:multistockfish/multistockfish.dart';

import 'uci.dart';

class _Search {
  _Search(this.onDepth);

  final void Function(int depth)? onDepth;
  final Completer<EngineResult?> completer = Completer<EngineResult?>();

  /// Baris terbaru per variasi MultiPV (1 dan 2).
  final Map<int, InfoLine> lines = <int, InfoLine>{};
  int depthSeen = 0;
  bool cancelled = false;

  void finish(EngineResult? result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}

/// Pembungkus Stockfish (UCI). Hanya satu instance engine dan satu pencarian
/// pada satu waktu. Engine baru dijalankan saat dibutuhkan (lazy).
///
/// Engine berjalan di thread native (bukan isolate UI), jadi UI tetap responsif.
class StockfishService {
  StockfishService._();

  static final StockfishService instance = StockfishService._();

  /// Kedalaman analisis: `go depth 22`, tanpa movetime atau batas lain.
  static const int analysisDepth = 22;

  /// Jumlah variasi yang dicari dan dilaporkan.
  static const int multiPv = 2;

  /// Thread pencarian: setengah dari jumlah core, minimal 1, maksimal 4.
  static final int threads =
      math.max(1, math.min(4, Platform.numberOfProcessors ~/ 2));

  /// Ukuran hash table (MB). Naikkan ke 128 bila HP kuat; turunkan bila RAM sempit.
  static const int hashMb = 64;

  Stockfish? _engine;
  StreamSubscription<String>? _sub;
  Future<void>? _shutdownFuture;
  Future<bool>? _startFuture;
  Completer<void>? _readyWaiter;
  _Search? _search;

  String? lastError;

  bool get isReady =>
      _engine != null && _engine!.state.value == StockfishState.ready;

  /// Menyalakan engine jika belum. Mengembalikan false bila gagal (tanpa crash).
  Future<bool> ensureStarted() {
    if (isReady) return Future<bool>.value(true);
    return _startFuture ??= _start().whenComplete(() {
      _startFuture = null;
    });
  }

  Future<bool> _start() async {
    try {
      final Future<void>? pending = _shutdownFuture;
      if (pending != null) await pending;
      await _disposeEngine();

      final Stockfish engine = await Stockfish.create();
      _engine = engine;
      _sub = engine.stdout.listen(_onLine);
      engine.state.addListener(_onEngineState);

      // Konfigurasi UCI. Tanpa Skill Level / UCI_Elo.
      _send('setoption name Threads value $threads');
      _send('setoption name Hash value $hashMb');
      _send('setoption name MultiPV value $multiPv');
      await _waitReady();

      lastError = null;
      return true;
    } catch (e) {
      lastError = e.toString();
      await _disposeEngine();
      return false;
    }
  }

  void _send(String command) {
    final Stockfish? engine = _engine;
    if (engine == null) return;
    engine.stdin = command;
  }

  Future<void> _waitReady() async {
    final Completer<void> waiter = Completer<void>();
    _readyWaiter = waiter;
    try {
      _send('isready');
      await waiter.future.timeout(const Duration(seconds: 10));
    } finally {
      _readyWaiter = null;
    }
  }

  /// Reset state engine sebelum sesi analisis baru.
  Future<void> newGame() async {
    if (!isReady) return;
    _send('ucinewgame');
    await _waitReady();
  }

  /// Engine mati di tengah analisis -> akhiri pencarian (hasil null).
  void _onEngineState() {
    final Stockfish? engine = _engine;
    if (engine == null) return;
    if (engine.state.value == StockfishState.ready) return;

    final _Search? search = _search;
    if (search != null) {
      search.cancelled = true;
      _search = null;
      search.finish(null);
    }
  }

  void _onLine(String line) {
    if (line == 'readyok') {
      final Completer<void>? waiter = _readyWaiter;
      if (waiter != null && !waiter.isCompleted) waiter.complete();
      return;
    }

    final _Search? search = _search;
    if (search == null) return;

    if (line.startsWith('bestmove')) {
      final List<String> parts = line.split(' ');
      final String? bm =
          parts.length > 1 && parts[1] != '(none)' ? parts[1] : null;
      _search = null;

      final InfoLine? l1 = search.lines[1];
      final InfoLine? l2 = search.lines[2];

      if (search.cancelled || l1 == null) {
        search.finish(null);
        return;
      }

      // Alternatif hanya dipakai bila berasal dari depth yang sama dengan MultiPV 1.
      final EngineLine? alternative = (l2 != null && l2.depth == l1.depth)
          ? EngineLine(score: l2.score, depth: l2.depth, pv: l2.pv)
          : null;

      search.finish(
        EngineResult(
          primary: EngineLine(score: l1.score, depth: l1.depth, pv: l1.pv),
          alternative: alternative,
          bestMove: bm ?? (l1.pv.isNotEmpty ? l1.pv.first : null),
        ),
      );
      return;
    }

    final InfoLine? info = parseInfoLine(line);
    if (info == null || info.multipv > multiPv) return;

    search.lines[info.multipv] = info;
    if (info.multipv == 1 && info.depth > search.depthSeen) {
      search.depthSeen = info.depth;
      search.onDepth?.call(info.depth);
    }
  }

  /// Analisis satu posisi: `position fen <FEN>` lalu `go depth 22`.
  /// Tanpa movetime atau batas waktu: berjalan sampai depth 22 selesai.
  /// Mengembalikan null bila dibatalkan atau engine gagal/mati.
  Future<EngineResult?> analyze(
    String fen, {
    void Function(int depth)? onDepth,
  }) async {
    if (_search != null) await cancel();
    if (!isReady) return null;

    final _Search search = _Search(onDepth);
    _search = search;
    _send('position fen $fen');
    _send('go depth $analysisDepth');
    return search.completer.future;
  }

  /// Membatalkan pencarian yang sedang berjalan dan menunggu engine berhenti.
  /// Jika engine tidak menjawab `stop`, engine dimatikan agar tidak macet.
  Future<void> cancel() async {
    final _Search? search = _search;
    if (search == null) return;
    search.cancelled = true;
    _send('stop');

    bool acknowledged = true;
    await search.completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        acknowledged = false;
        return null;
      },
    );
    if (!acknowledged) await _disposeEngine();
  }

  /// Menghentikan analisis dan mematikan engine (membebaskan memori).
  Future<void> shutdown() {
    final Future<void> job = () async {
      await cancel();
      await _disposeEngine();
    }();
    final Future<void> tracked = job.whenComplete(() {
      _shutdownFuture = null;
    });
    _shutdownFuture = tracked;
    return tracked;
  }

  Future<void> _disposeEngine() async {
    final Stockfish? engine = _engine;
    final StreamSubscription<String>? sub = _sub;
    _engine = null;
    _sub = null;

    engine?.state.removeListener(_onEngineState);

    final _Search? search = _search;
    _search = null;
    if (search != null) {
      search.cancelled = true;
      search.finish(null);
    }

    await sub?.cancel();
    try {
      await engine?.dispose();
    } catch (_) {
      // Engine sudah mati; abaikan.
    }
  }
}
