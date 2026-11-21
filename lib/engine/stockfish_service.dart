import 'dart:async';

import 'package:multistockfish/multistockfish.dart';

import 'uci.dart';

class _Search {
  final Completer<EngineResult?> completer = Completer<EngineResult?>();
  InfoLine? best;
  bool cancelled = false;

  void finish(EngineResult? result) {
    if (!completer.isCompleted) completer.complete(result);
  }
}

/// Pembungkus Stockfish (UCI). Hanya satu instance engine dan satu pencarian
/// pada satu waktu. Engine baru dijalankan saat dibutuhkan (lazy).
class StockfishService {
  StockfishService._();

  static final StockfishService instance = StockfishService._();

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

      // Aman untuk HP low-end. Tanpa Skill Level / UCI_Elo.
      _send('setoption name Threads value 1');
      _send('setoption name Hash value 32');
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

      final InfoLine? best = search.best;
      if (search.cancelled || best == null) {
        search.finish(null);
      } else {
        search.finish(
          EngineResult(
            score: best.score,
            depth: best.depth,
            pv: best.pv,
            bestMove: bm ?? (best.pv.isNotEmpty ? best.pv.first : null),
          ),
        );
      }
      return;
    }

    final InfoLine? info = parseInfoLine(line);
    if (info != null) search.best = info;
  }

  /// Analisis satu posisi: `go depth 20 movetime 5000`.
  /// Mengembalikan null bila dibatalkan, engine belum siap, atau timeout.
  Future<EngineResult?> analyze(
    String fen, {
    int depth = 20,
    int movetimeMs = 5000,
  }) async {
    if (_search != null) await cancel();
    if (!isReady) return null;

    final _Search search = _Search();
    _search = search;
    _send('position fen $fen');
    _send('go depth $depth movetime $movetimeMs');

    return search.completer.future.timeout(
      Duration(milliseconds: movetimeMs + 20000),
      onTimeout: () {
        search.cancelled = true;
        if (identical(_search, search)) {
          _search = null;
          _send('stop');
        }
        return null;
      },
    );
  }

  /// Membatalkan pencarian yang sedang berjalan dan menunggu engine berhenti.
  Future<void> cancel() async {
    final _Search? search = _search;
    if (search == null) return;
    search.cancelled = true;
    _send('stop');
    await search.completer.future.timeout(
      const Duration(seconds: 3),
      onTimeout: () {
        if (identical(_search, search)) _search = null;
        return null;
      },
    );
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
