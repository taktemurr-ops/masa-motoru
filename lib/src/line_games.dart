import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Sıraya dizme oyunları: XOX, Dörtle (yerçekimli), Beşleme.
/// [k] taş yan yana (yatay, dikey, çapraz) dizen kazanır.
class LineRules extends BoardRules<GridState> {
  final int cols, rows, k;
  final bool gravity;

  /// Beşleme için: tam k gerekir (k+1 sayılmaz) mı.
  final bool exact;
  @override
  final String id;
  const LineRules(this.id, this.cols, this.rows, this.k, {this.gravity = false, this.exact = false});

  static final _windowCache = <String, List<List<int>>>{};

  /// Tahtadaki bütün k'lık pencereler.
  List<List<int>> get windows => _windowCache.putIfAbsent('$cols/$rows/$k', () {
        final out = <List<int>>[];
        const dirs = [(1, 0), (0, 1), (1, 1), (1, -1)];
        for (var r = 0; r < rows; r++) {
          for (var c = 0; c < cols; c++) {
            for (final (dc, dr) in dirs) {
              final ec = c + dc * (k - 1), er = r + dr * (k - 1);
              if (ec < 0 || ec >= cols || er < 0 || er >= rows) continue;
              out.add([for (var i = 0; i < k; i++) (r + dr * i) * cols + c + dc * i]);
            }
          }
        }
        return out;
      });

  static final _cellWindows = <String, List<List<int>>>{};
  List<List<int>> get cellWindows => _cellWindows.putIfAbsent('$cols/$rows/$k', () {
        final out = List.generate(cols * rows, (_) => <int>[]);
        final ws = windows;
        for (var i = 0; i < ws.length; i++) {
          for (final c in ws[i]) {
            out[c].add(i);
          }
        }
        return out;
      });

  @override
  int get maxPly => cols * rows + 1;

  @override
  GridState initial(SeededRandom r) => GridState(cols, rows, List.filled(cols * rows, -1));

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    if (gravity) {
      final out = <int>[];
      for (var c = 0; c < cols; c++) {
        for (var r = rows - 1; r >= 0; r--) {
          if (s.cells[r * cols + c] < 0) {
            out.add(mv(-1, r * cols + c));
            break;
          }
        }
      }
      return out;
    }
    return [for (var i = 0; i < s.cells.length; i++) if (s.cells[i] < 0) mv(-1, i)];
  }

  /// Büyük tahtada yalnızca taşların yakınındaki boşluklar.
  @override
  List<int> searchMoves(GridState s) {
    if (gravity || cols * rows <= 25) return moves(s);
    if (s.cells.every((x) => x < 0)) return [mv(-1, (rows ~/ 2) * cols + cols ~/ 2)];
    final near = <int>{};
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] < 0) continue;
      final c = i % cols, r = i ~/ cols;
      for (var dr = -2; dr <= 2; dr++) {
        for (var dc = -2; dc <= 2; dc++) {
          final nc = c + dc, nr = r + dr;
          if (s.inside(nc, nr) && s.cells[nr * cols + nc] < 0 && (dr.abs() <= 1 && dc.abs() <= 1 || dr == 0 || dc == 0 || dr.abs() == dc.abs())) {
            near.add(nr * cols + nc);
          }
        }
      }
    }
    final ms = [for (final i in near) mv(-1, i)]..sort((a, b) => moveOrder(s, b).compareTo(moveOrder(s, a)));
    return ms.length > 14 ? ms.sublist(0, 14) : ms;
  }

  @override
  int moveOrder(GridState s, int m) {
    final cell = mvTo(m);
    var score = 0;
    final ws = windows;
    for (final wi in cellWindows[cell]) {
      var mine = 0, theirs = 0;
      for (final c in ws[wi]) {
        final v = s.cells[c];
        if (v == s.turn) mine++;
        if (v == 1 - s.turn) theirs++;
      }
      if (theirs == 0) score += const [1, 4, 20, 120, 900, 9000, 90000][mine.clamp(0, 6)];
      if (mine == 0) score += const [0, 3, 15, 100, 800, 8000, 80000][theirs.clamp(0, 6)];
    }
    return score;
  }

  @override
  void apply(GridState s, int m) {
    final cell = mvTo(m);
    final p = s.turn;
    s.cells[cell] = p;
    s.last = cell;
    s.ply++;
    if (winsAt(s, cell, p)) {
      s.vars[0] = p + 1;
    } else if (!s.cells.contains(-1)) {
      s.vars[0] = 3;
    }
    s.turn = 1 - p;
  }

  bool winsAt(GridState s, int cell, int p) {
    final c0 = cell % cols, r0 = cell ~/ cols;
    for (final (dc, dr) in const [(1, 0), (0, 1), (1, 1), (1, -1)]) {
      var n = 1;
      for (var sgn = -1; sgn <= 1; sgn += 2) {
        var c = c0 + dc * sgn, r = r0 + dr * sgn;
        while (s.inside(c, r) && s.cells[r * cols + c] == p) {
          n++;
          c += dc * sgn;
          r += dr * sgn;
        }
      }
      if (exact ? n == k : n >= k) return true;
    }
    return false;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 1 ? 0 : (s.vars[0] == 2 ? 1 : -1);

  @override
  double evaluate(GridState s, int player) {
    var v = 0.0;
    for (final w in windows) {
      var a = 0, b = 0;
      for (final c in w) {
        final x = s.cells[c];
        if (x == player) a++;
        if (x == 1 - player) b++;
      }
      if (b == 0 && a > 0) v += _weight(a) * (s.turn == player ? 1.3 : 1.0);
      if (a == 0 && b > 0) v -= _weight(b) * (s.turn == player ? 1.0 : 1.5);
    }
    return (v / (k * 3)).clamp(-99, 99).toDouble();
  }

  double _weight(int n) => switch (k - n) { 0 => 1000, 1 => 60, 2 => 12, 3 => 2, _ => 0.4 };

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
