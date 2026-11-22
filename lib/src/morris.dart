import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Dokuz taş: 24 nokta. Önce taşlar sırayla konur, sonra komşu noktaya
/// yürünür; üç taşı kalan uçabilir. Üçlü (dizi) kuran rakibin bir taşını alır.
/// Taşı ikiye inen ya da hamlesi kalmayan kaybeder.
/// vars: [0] bitti, [1..2] konan taş sayısı, [3] alma bekliyor (1),
/// [4] alımsız hamle sayacı.
class MorrisRules extends BoardRules<GridState> {
  final int men;
  const MorrisRules([this.men = 9]);

  @override
  String get id => 'dokuz-tas';

  /// Noktaların 7×7 ızgaradaki yerleri.
  static const points = [
    (0, 0), (3, 0), (6, 0), (1, 1), (3, 1), (5, 1), (2, 2), (3, 2), (4, 2), //
    (0, 3), (1, 3), (2, 3), (4, 3), (5, 3), (6, 3), //
    (2, 4), (3, 4), (4, 4), (1, 5), (3, 5), (5, 5), (0, 6), (3, 6), (6, 6),
  ];

  static const adj = [
    [1, 9], [0, 2, 4], [1, 14], [4, 10], [1, 3, 5, 7], [4, 13], [7, 11], [4, 6, 8], [7, 12], //
    [0, 10, 21], [3, 9, 11, 18], [6, 10, 15], [8, 13, 17], [5, 12, 14, 20], [2, 13, 23], //
    [11, 16], [15, 17, 19], [12, 16], [10, 19], [16, 18, 20, 22], [13, 19], [9, 22], [19, 21, 23], [14, 22],
  ];

  static const mills = [
    [0, 1, 2], [3, 4, 5], [6, 7, 8], [9, 10, 11], [12, 13, 14], [15, 16, 17], [18, 19, 20], [21, 22, 23], //
    [0, 9, 21], [3, 10, 18], [6, 11, 15], [1, 4, 7], [16, 19, 22], [8, 12, 17], [5, 13, 20], [2, 14, 23],
  ];

  @override
  int get maxPly => 300;

  @override
  GridState initial(SeededRandom r) => GridState(24, 1, List.filled(24, -1));

  int onBoard(GridState s, int p) => s.cells.where((x) => x == p).length;
  bool placing(GridState s, int p) => s.vars[1 + p] < men;

  bool inMill(GridState s, int i) {
    final p = s.cells[i];
    if (p < 0) return false;
    for (final m in mills) {
      if (m.contains(i) && m.every((j) => s.cells[j] == p)) return true;
    }
    return false;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final p = s.turn;
    if (s.vars[3] == 1) {
      final theirs = [for (var i = 0; i < 24; i++) if (s.cells[i] == 1 - p) i];
      final free = theirs.where((i) => !inMill(s, i)).toList();
      return [for (final i in free.isEmpty ? theirs : free) mv(-1, i, 1)];
    }
    if (placing(s, p)) return [for (var i = 0; i < 24; i++) if (s.cells[i] < 0) mv(-1, i)];
    final fly = onBoard(s, p) == 3;
    final out = <int>[];
    for (var i = 0; i < 24; i++) {
      if (s.cells[i] != p) continue;
      for (final j in fly ? List.generate(24, (k) => k) : adj[i]) {
        if (s.cells[j] < 0) out.add(mv(i, j));
      }
    }
    return out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final to = mvTo(m), from = mvFrom(m);
    s.ply++;
    if (mvExtra(m) == 1) {
      s.cells[to] = -1;
      s.vars[3] = 0;
      s.vars[4] = 0;
      s.turn = 1 - p;
      s.last = -1;
      _end(s);
      return;
    }
    if (from < 0) {
      s.vars[1 + p]++;
    } else {
      s.cells[from] = -1;
    }
    s.cells[to] = p;
    s.last = to;
    s.vars[4]++;
    if (inMill(s, to)) {
      s.vars[3] = 1;
      return; // aynı oyuncu taş alacak
    }
    s.turn = 1 - p;
    _end(s);
  }

  void _end(GridState s) {
    final p = s.turn;
    if (!placing(s, p) && onBoard(s, p) < 3) {
      s.vars[0] = 1;
      return;
    }
    if (moves(s).isEmpty) s.vars[0] = 1;
    if (s.vars[4] >= 60) s.vars[0] = 2; // uzun süre alımsız: berabere
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 1 ? 1 - s.turn : -1;

  @override
  int moveOrder(GridState s, int m) {
    final c = s.copy();
    apply(c, m);
    return c.vars[3] == 1 ? 50 : 0;
  }

  @override
  double evaluate(GridState s, int player) {
    final o = 1 - player;
    final pieces = (onBoard(s, player) + men - s.vars[1 + player]) - (onBoard(s, o) + men - s.vars[1 + o]);
    var twos = 0;
    for (final m in mills) {
      final a = m.where((j) => s.cells[j] == player).length, b = m.where((j) => s.cells[j] == o).length;
      final e = m.where((j) => s.cells[j] < 0).length;
      if (a == 2 && e == 1) twos++;
      if (b == 2 && e == 1) twos--;
    }
    var mob = 0;
    if (!placing(s, player) && !placing(s, o)) {
      for (var i = 0; i < 24; i++) {
        if (s.cells[i] < 0) continue;
        final free = adj[i].where((j) => s.cells[j] < 0).length;
        mob += s.cells[i] == player ? free : -free;
      }
    }
    return pieces * 12.0 + twos * 3 + mob * 0.6 + (s.vars[3] == 1 ? (s.turn == player ? 10 : -10) : 0);
  }

  @override
  String status(GridState s, String lang) =>
      '● ${onBoard(s, 0) + men - s.vars[1]}  ·  ○ ${onBoard(s, 1) + men - s.vars[2]}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
