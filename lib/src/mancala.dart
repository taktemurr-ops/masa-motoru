import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Mangala ailesi. Çukurlar: oyuncu 0 için 0..p-1, hazinesi p; oyuncu 1 için
/// p+1..2p, hazinesi 2p+1. Tohumlar saat yönünün tersine dağıtılır.
/// vars[0]: bitti (1).
enum MancalaCapture {
  /// Mangala: rakip çukurdaki sayı çift olursa al; boş kendi çukuruna son
  /// taş düşerse karşıdakiyle birlikte al.
  mangala,

  /// Kalah: son taş kendi boş çukuruna düşerse karşıdakiyle al.
  kalah,

  /// Oware: son taş rakip çukurda sayıyı 2 ya da 3 yaparsa al; geriye doğru
  /// zincirle devam et. Hazine yok, alınanlar kenara konur.
  oware,
}

class MancalaRules extends BoardRules<GridState> {
  @override
  final String id;
  final int pits, seeds;
  final MancalaCapture capture;
  const MancalaRules(this.id, {this.pits = 6, this.seeds = 4, this.capture = MancalaCapture.mangala});

  static const mangala = MancalaRules('mangala');
  static const kalah = MancalaRules('kalah', capture: MancalaCapture.kalah);
  static const oware = MancalaRules('oware', capture: MancalaCapture.oware);

  int store(int p) => p == 0 ? pits : 2 * pits + 1;
  int get total => 2 * pits * seeds;
  bool own(int i, int p) => p == 0 ? i < pits : (i > pits && i < 2 * pits + 1);
  int opposite(int i) => 2 * pits - i;

  @override
  int get maxPly => 300;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(2 * pits + 2, 1, List.filled(2 * pits + 2, seeds));
    s.cells[pits] = 0;
    s.cells[2 * pits + 1] = 0;
    return s;
  }

  bool _sideEmpty(GridState s, int p) {
    for (var i = 0; i < 2 * pits + 2; i++) {
      if (own(i, p) && s.cells[i] > 0) return false;
    }
    return true;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    for (var i = 0; i < 2 * pits + 2; i++) {
      if (!own(i, p) || s.cells[i] == 0) continue;
      if (capture == MancalaCapture.oware && !_feeds(s, i)) continue;
      out.add(mv(-1, i));
    }
    if (out.isEmpty && capture == MancalaCapture.oware) {
      // Rakibi besleyen hamle yoksa her hamle serbest.
      for (var i = 0; i < 2 * pits + 2; i++) {
        if (own(i, p) && s.cells[i] > 0) out.add(mv(-1, i));
      }
    }
    return out;
  }

  /// Oware: rakibin hiç tohumu yoksa ona tohum götüren hamle zorunlu.
  bool _feeds(GridState s, int i) {
    final o = 1 - s.turn;
    if (!_sideEmpty(s, o)) return true;
    final c = s.copy();
    _sow(c, i);
    return !_sideEmpty(c, o);
  }

  int _next(int i, int p) {
    var j = (i + 1) % (2 * pits + 2);
    if (j == store(1 - p) || (capture == MancalaCapture.oware && (j == pits || j == 2 * pits + 1))) j = (j + 1) % (2 * pits + 2);
    return j;
  }

  /// Dağıt; son tohumun düştüğü yeri döndür.
  int _sow(GridState s, int from) {
    final p = s.turn;
    var n = s.cells[from];
    s.cells[from] = 0;
    var at = from;
    if (capture == MancalaCapture.mangala) {
      if (n == 1) {
        at = _next(from, p);
        s.cells[at]++;
        return at;
      }
      s.cells[from] = 1; // ilk taş aldığı çukura
      n--;
    }
    while (n > 0) {
      at = _next(at, p);
      if (capture == MancalaCapture.oware && at == from) continue; // 12+ tohumda başlangıç atlanır
      s.cells[at]++;
      n--;
    }
    return at;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final from = mvTo(m);
    final last = _sow(s, from);
    s.last = from;
    s.ply++;
    var again = false;
    switch (capture) {
      case MancalaCapture.mangala:
        if (last == store(p)) {
          again = true;
        } else if (own(last, 1 - p) && s.cells[last] % 2 == 0) {
          s.cells[store(p)] += s.cells[last];
          s.cells[last] = 0;
        } else if (own(last, p) && s.cells[last] == 1 && s.cells[opposite(last)] > 0) {
          s.cells[store(p)] += 1 + s.cells[opposite(last)];
          s.cells[last] = 0;
          s.cells[opposite(last)] = 0;
        }
      case MancalaCapture.kalah:
        if (last == store(p)) {
          again = true;
        } else if (own(last, p) && s.cells[last] == 1 && s.cells[opposite(last)] > 0) {
          s.cells[store(p)] += 1 + s.cells[opposite(last)];
          s.cells[last] = 0;
          s.cells[opposite(last)] = 0;
        }
      case MancalaCapture.oware:
        if (own(last, 1 - p)) {
          final saved = List.of(s.cells);
          var at = last, got = 0;
          while (own(at, 1 - p) && (s.cells[at] == 2 || s.cells[at] == 3)) {
            got += s.cells[at];
            s.cells[at] = 0;
            at = at - 1;
          }
          if (_sideEmpty(s, 1 - p)) {
            // Rakibin bütün tohumlarını alan hamle almaz (büyük vuruş yok).
            s.cells
              ..clear()
              ..addAll(saved);
          } else {
            s.cells[store(p)] += got;
          }
        }
    }
    if (!again) s.turn = 1 - p;
    _checkEnd(s);
  }

  void _checkEnd(GridState s) {
    final half = total ~/ 2;
    if (capture == MancalaCapture.oware) {
      if (s.cells[store(0)] > half || s.cells[store(1)] > half) {
        s.vars[0] = 1;
        return;
      }
      if (moves(s).isEmpty || s.ply >= maxPly - 1) {
        // Kalan tohumlar sahiplerine.
        for (var i = 0; i < 2 * pits + 2; i++) {
          if (i == store(0) || i == store(1)) continue;
          s.cells[store(own(i, 0) ? 0 : 1)] += s.cells[i];
          s.cells[i] = 0;
        }
        s.vars[0] = 1;
      }
      return;
    }
    for (final p in const [0, 1]) {
      if (_sideEmpty(s, p)) {
        // Mangala: çukurları boşalan, rakibin kalan taşlarını alır.
        final taker = capture == MancalaCapture.mangala ? p : 1 - p;
        for (var i = 0; i < 2 * pits + 2; i++) {
          if (own(i, 1 - p)) {
            s.cells[store(taker)] += s.cells[i];
            s.cells[i] = 0;
          }
        }
        s.vars[0] = 1;
        return;
      }
    }
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) {
    final a = s.cells[store(0)], b = s.cells[store(1)];
    return a == b ? -1 : (a > b ? 0 : 1);
  }

  @override
  int moveOrder(GridState s, int m) {
    final c = s.copy();
    final p = s.turn;
    apply(c, m);
    return (c.cells[store(p)] - s.cells[store(p)]) * 10 + (c.turn == p ? 15 : 0);
  }

  @override
  double evaluate(GridState s, int player) {
    final o = 1 - player;
    var side = 0;
    for (var i = 0; i < 2 * pits + 2; i++) {
      if (own(i, player)) side += s.cells[i];
      if (own(i, o)) side -= s.cells[i];
    }
    return (s.cells[store(player)] - s.cells[store(o)]) * 4.0 + side * 0.5;
  }

  @override
  String status(GridState s, String lang) => '${s.cells[store(0)]} : ${s.cells[store(1)]}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
