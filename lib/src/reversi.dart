import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Reversi: taşını koyduğun yerle kendi taşın arasında kalan rakip taşlar
/// döner. Hamlesi olmayan pas geçer; ikisi de oynayamazsa çok taşı olan kazanır.
/// vars[0]: bitti mi (1), vars[1]: üst üste pas sayısı.
class ReversiRules extends BoardRules<GridState> {
  final int n;
  const ReversiRules([this.n = 8]);

  @override
  String get id => 'reversi';

  @override
  int get maxPly => n * n * 2;

  static const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)];

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(n, n, List.filled(n * n, -1));
    final h = n ~/ 2;
    s.cells[(h - 1) * n + h - 1] = 1;
    s.cells[h * n + h] = 1;
    s.cells[(h - 1) * n + h] = 0;
    s.cells[h * n + h - 1] = 0;
    return s;
  }

  List<int> _flips(GridState s, int cell, int p) {
    final out = <int>[];
    final c0 = cell % n, r0 = cell ~/ n;
    for (final (dc, dr) in _dirs) {
      final line = <int>[];
      var c = c0 + dc, r = r0 + dr;
      while (s.inside(c, r) && s.cells[r * n + c] == 1 - p) {
        line.add(r * n + c);
        c += dc;
        r += dr;
      }
      if (line.isNotEmpty && s.inside(c, r) && s.cells[r * n + c] == p) out.addAll(line);
    }
    return out;
  }

  List<int> _legal(GridState s, int p) => [
        for (var i = 0; i < s.cells.length; i++)
          if (s.cells[i] < 0 && _flips(s, i, p).isNotEmpty) mv(-1, i)
      ];

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final l = _legal(s, s.turn);
    return l.isEmpty ? const [kPass] : l;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m == kPass) {
      s.vars[1]++;
      s.last = -1;
    } else {
      final cell = mvTo(m);
      for (final f in _flips(s, cell, p)) {
        s.cells[f] = p;
      }
      s.cells[cell] = p;
      s.last = cell;
      s.vars[1] = 0;
    }
    s.turn = 1 - p;
    if (s.vars[1] >= 2 || !s.cells.contains(-1)) s.vars[0] = 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  int count(GridState s, int p) => s.cells.where((x) => x == p).length;

  @override
  int winner(GridState s) {
    final a = count(s, 0), b = count(s, 1);
    return a == b ? -1 : (a > b ? 0 : 1);
  }

  bool _corner(int i) {
    final c = i % n, r = i ~/ n;
    return (c == 0 || c == n - 1) && (r == 0 || r == n - 1);
  }

  bool _xSquare(int i) {
    final c = i % n, r = i ~/ n;
    return (c == 1 || c == n - 2) && (r == 1 || r == n - 2);
  }

  @override
  int moveOrder(GridState s, int m) {
    if (m == kPass) return 0;
    final i = mvTo(m);
    if (_corner(i)) return 100;
    if (_xSquare(i)) return -50;
    final c = i % n, r = i ~/ n;
    return (c == 0 || r == 0 || c == n - 1 || r == n - 1) ? 20 : 0;
  }

  @override
  double evaluate(GridState s, int player) {
    final o = 1 - player;
    var corner = 0.0, edge = 0.0, x = 0.0;
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (v < 0) continue;
      final sign = v == player ? 1 : -1;
      if (_corner(i)) {
        corner += sign;
      } else if (_xSquare(i)) {
        x += sign;
      } else {
        final c = i % n, r = i ~/ n;
        if (c == 0 || r == 0 || c == n - 1 || r == n - 1) edge += sign;
      }
    }
    final mob = _legal(s, player).length - _legal(s, o).length;
    final empties = s.cells.where((v) => v < 0).length;
    final disc = count(s, player) - count(s, o);
    final late = empties < n * n / 4;
    return corner * 25 + edge * 2 - x * 8 + mob * 2 + (late ? disc * 1.5 : disc * 0.1);
  }

  @override
  String status(GridState s, String lang) => '● ${count(s, 0)}  ·  ○ ${count(s, 1)}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

