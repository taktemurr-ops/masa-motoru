import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

// ======================================================================
// Fanorona: 9×5 çizgili tahta. Alım yaklaşarak ya da uzaklaşarak yapılır;
// bir sıradaki bitişik rakip taşların hepsi alınır. Alım zorunludur ve aynı
// taşla sürdürülebilir (aynı yöne ve aynı noktaya ikinci kez gidilmez).
// vars: [0] sonuç (kazanan+1, 3 berabere), [1] zincirdeki taş+1, [2] son
// yön+1, [3]/[4] bu turda uğranan noktalar (bit), [5] alımsız hamle sayacı.

class FanoronaRules extends BoardRules<GridState> {
  const FanoronaRules();

  @override
  String get id => 'fanorona';

  static const cols = 9, rows = 5;

  @override
  int get maxPly => 260;

  @override
  double get decisive => 60;

  static const dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)];

  static bool diagonalAt(int i) => (i % cols + i ~/ cols).isEven;
  static bool _in(int c, int r) => c >= 0 && r >= 0 && c < cols && r < rows;

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(cols * rows, -1);
    for (var i = 0; i < cols * rows; i++) {
      final r = i ~/ cols;
      if (r < 2) cells[i] = 1;
      if (r > 2) cells[i] = 0;
    }
    const mid = [1, 0, 1, 0, -1, 1, 0, 1, 0];
    for (var c = 0; c < cols; c++) {
      cells[2 * cols + c] = mid[c];
    }
    return GridState(cols, rows, cells);
  }

  bool _visited(GridState s, int i) => i < 30 ? (s.vars[3] >> i) & 1 == 1 : (s.vars[4] >> (i - 30)) & 1 == 1;
  void _visit(GridState s, int i) {
    if (i < 30) {
      s.vars[3] |= 1 << i;
    } else {
      s.vars[4] |= 1 << (i - 30);
    }
  }

  /// Bir yönde art arda rakip taşlar.
  List<int> _run(GridState s, int c, int r, int dc, int dr, int enemy) {
    final out = <int>[];
    while (_in(c, r) && s.cells[r * cols + c] == enemy) {
      out.add(r * cols + c);
      c += dc;
      r += dr;
    }
    return out;
  }

  /// [from]→yön [d] alımı: (hedef, alınanlar, tür 1 yaklaşma / 2 uzaklaşma).
  (int, List<int>, int)? _capture(GridState s, int from, int d) {
    final p = s.cells[from];
    final (dc, dr) = dirs[d];
    if (d >= 4 && !diagonalAt(from)) return null;
    final c0 = from % cols, r0 = from ~/ cols;
    final tc = c0 + dc, tr = r0 + dr;
    if (!_in(tc, tr) || s.cells[tr * cols + tc] != -1) return null;
    final app = _run(s, tc + dc, tr + dr, dc, dr, 1 - p);
    final wd = _run(s, c0 - dc, r0 - dr, -dc, -dr, 1 - p);
    if (app.isEmpty && wd.isEmpty) return null;
    return app.length >= wd.length ? (tr * cols + tc, app, 1) : (tr * cols + tc, wd, 2);
  }

  List<(int, List<int>)> _all(GridState s) {
    final p = s.turn;
    final out = <(int, List<int>)>[];
    if (s.vars[1] > 0) {
      final from = s.vars[1] - 1;
      for (var d = 0; d < 8; d++) {
        if (d + 1 == s.vars[2]) continue;
        final cap = _capture(s, from, d);
        if (cap == null || _visited(s, cap.$1)) continue;
        out.add((mv(from, cap.$1, cap.$3), cap.$2));
      }
      out.add((kPass, const []));
      return out;
    }
    for (var i = 0; i < cols * rows; i++) {
      if (s.cells[i] != p) continue;
      for (var d = 0; d < 8; d++) {
        final cap = _capture(s, i, d);
        if (cap != null) out.add((mv(i, cap.$1, cap.$3), cap.$2));
      }
    }
    if (out.isNotEmpty) return out;
    for (var i = 0; i < cols * rows; i++) {
      if (s.cells[i] != p) continue;
      for (var d = 0; d < 8; d++) {
        if (d >= 4 && !diagonalAt(i)) continue;
        final (dc, dr) = dirs[d];
        final c = i % cols + dc, r = i ~/ cols + dr;
        if (_in(c, r) && s.cells[r * cols + c] == -1) out.add((mv(i, r * cols + c), const []));
      }
    }
    return out;
  }

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : [for (final x in _all(s)) x.$1];

  @override
  int moveOrder(GridState s, int m) {
    if (m == kPass) return -1;
    for (final (code, t) in _all(s)) {
      if (code == m) return t.length;
    }
    return 0;
  }

  void _endTurn(GridState s) {
    s.vars[1] = s.vars[2] = s.vars[3] = s.vars[4] = 0;
    s.turn = 1 - s.turn;
    final mine = s.cells.where((x) => x == s.turn).length;
    if (mine == 0) {
      s.vars[0] = 2 - s.turn;
    } else if (s.vars[5] >= 50) {
      s.vars[0] = 3;
    } else if (_all(s).isEmpty) {
      s.vars[0] = 2 - s.turn;
    }
  }

  @override
  void apply(GridState s, int m) {
    s.ply++;
    if (m == kPass) {
      _endTurn(s);
      return;
    }
    var taken = const <int>[];
    for (final (code, t) in _all(s)) {
      if (code == m) {
        taken = t;
        break;
      }
    }
    final from = mvFrom(m), to = mvTo(m), p = s.turn;
    s.cells[to] = p;
    s.cells[from] = -1;
    s.last = to;
    for (final t in taken) {
      s.cells[t] = -1;
    }
    if (taken.isEmpty) {
      s.vars[5]++;
      _endTurn(s);
      return;
    }
    s.vars[5] = 0;
    final dc = to % cols - from % cols, dr = to ~/ cols - from ~/ cols;
    _visit(s, from);
    _visit(s, to);
    s.vars[1] = to + 1;
    s.vars[2] = dirs.indexOf((dc, dr)) + 1;
    if (s.cells.where((x) => x == 1 - p).isEmpty) {
      s.vars[0] = p + 1;
      return;
    }
    // Zincir sürebilir mi? Yoksa sıra geçer.
    if (_all(s).length == 1) _endTurn(s);
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 3 ? -1 : s.vars[0] - 1;

  @override
  double evaluate(GridState s, int player) {
    final a = s.cells.where((x) => x == player).length, b = s.cells.where((x) => x == 1 - player).length;
    return ((a - b) * 6.0 + (a + b > 0 ? (a - b) * 20.0 / (a + b) : 0)).clamp(-99, 99).toDouble();
  }

  @override
  String status(GridState s, String lang) => '● ${s.cells.where((x) => x == 0).length} · ${s.cells.where((x) => x == 1).length}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Mermer itme: altıgen tahtada (61 delik) 14'er bilye. Bir, iki ya da üç
// bilyelik sıra kendi yönünde ilerler; daha az sayıdaki rakip bilyeleri
// iter. Tahtadan altı rakip bilye düşüren kazanır.
// vars: [0] sonuç, [2]/[3] oyuncu 0/1'in düşürdüğü bilye.

class MarblePushRules extends BoardRules<GridState> {
  const MarblePushRules();

  @override
  String get id => 'mermer-itme';

  static const w = 9, m = 4;

  @override
  int get maxPly => 300;

  @override
  double get decisive => 70;

  static const dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];

  static bool valid(int q, int r) {
    final x = q - m, z = r - m, y = -x - z;
    return q >= 0 && r >= 0 && q < w && r < w && x.abs() <= m && z.abs() <= m && y.abs() <= m;
  }

  static int hexDist(int i) {
    final x = i % w - m, z = i ~/ w - m;
    return (x.abs() + z.abs() + (x + z).abs()) ~/ 2;
  }

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(w * w, -2);
    for (var r = 0; r < w; r++) {
      for (var q = 0; q < w; q++) {
        if (!valid(q, r)) continue;
        final x = q - m, z = r - m;
        var v = -1;
        if (z >= 3 || (z == 2 && x >= -2 && x <= 0)) v = 0;
        if (z <= -3 || (z == -2 && x >= 0 && x <= 2)) v = 1;
        cells[r * w + q] = v;
      }
    }
    return GridState(w, w, cells);
  }

  int? _at(int q, int r) => valid(q, r) ? r * w + q : null;

  /// (from, to) için yön ve sıra boyu.
  (int, int)? decode(int from, int to) {
    final fq = from % w, fr = from ~/ w, tq = to % w, tr = to ~/ w;
    for (var d = 0; d < 6; d++) {
      final (dq, dr) = dirs[d];
      for (var k = 1; k <= 3; k++) {
        if (fq + dq * k == tq && fr + dr * k == tr) return (d, k);
      }
    }
    return null;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] != p) continue;
      final q0 = i % w, r0 = i ~/ w;
      for (final (dq, dr) in dirs) {
        for (var k = 1; k <= 3; k++) {
          // i, i+d, ..., i+(k-1)d kendi bilyeleri olmalı.
          final last = _at(q0 + dq * (k - 1), r0 + dr * (k - 1));
          if (last == null || s.cells[last] != p) break;
          final n = _at(q0 + dq * k, r0 + dr * k);
          if (n == null) break;
          final v = s.cells[n];
          if (v == -1) {
            out.add(mv(i, n));
            break;
          }
          if (v == p) continue;
          // Rakip: sayısı az ise ve arkası boş ya da tahta dışıysa itilir.
          var e = 0;
          var after = n;
          while (true) {
            final c = _at(q0 + dq * (k + e), r0 + dr * (k + e));
            if (c == null || s.cells[c] != 1 - p) {
              after = c ?? -1;
              break;
            }
            e++;
          }
          if (e < k && (after == -1 || s.cells[after] == -1)) out.add(mv(i, n, 1));
          break;
        }
      }
    }
    return out.isEmpty ? const [kPass] : out;
  }

  @override
  int moveOrder(GridState s, int m) => m == kPass ? -9 : mvExtra(m) * 10 + (4 - hexDist(mvTo(m)));

  @override
  List<int> searchMoves(GridState s) {
    final ms = moves(s)..sort((a, b) => moveOrder(s, b).compareTo(moveOrder(s, a)));
    return ms.length > 24 ? ms.sublist(0, 24) : ms;
  }

  @override
  void apply(GridState s, int mv0) {
    final p = s.turn;
    s.ply++;
    if (mv0 != kPass) {
      final from = mvFrom(mv0), to = mvTo(mv0);
      final (d, _) = decode(from, to)!;
      final (dq, dr) = dirs[d];
      // Sıradaki bütün bilyeler (kendi + itilen) bir adım ilerler.
      final line = <int>[];
      var q = from % w, r = from ~/ w;
      while (true) {
        final c = _at(q, r);
        if (c == null || s.cells[c] < 0) break;
        line.add(c);
        q += dq;
        r += dr;
      }
      final beyond = _at(q, r);
      final tail = s.cells[line.last];
      if (beyond != null) {
        s.cells[beyond] = tail;
      } else if (tail == 1 - p) {
        s.vars[2 + p]++;
      }
      for (var j = line.length - 1; j >= 1; j--) {
        s.cells[line[j]] = s.cells[line[j - 1]];
      }
      s.cells[from] = -1;
      s.last = to;
    }
    s.turn = 1 - p;
    if (s.vars[2 + p] >= 6) {
      s.vars[0] = p + 1;
    } else if (s.ply >= maxPly) {
      final a = s.vars[2], b = s.vars[3];
      s.vars[0] = a == b ? 3 : (a > b ? 1 : 2);
    }
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 3 ? -1 : s.vars[0] - 1;

  @override
  double evaluate(GridState s, int player) {
    var v = (s.vars[2 + player] - s.vars[3 - player]) * 22.0;
    for (var i = 0; i < s.cells.length; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      final c = (4 - hexDist(i)) * 0.9;
      v += x == player ? c : -c;
    }
    return v.clamp(-99, 99).toDouble();
  }

  @override
  String status(GridState s, String lang) => '⬤ ${s.vars[2]} · ${s.vars[3]}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Duvar yarışı: piyonunu karşı kenara ilk ulaştıran kazanır; her turda ya
// piyon yürür ya da iki kare uzunluğunda bir duvar konur. Duvar hiçbir
// oyuncunun yolunu tamamen kapatamaz.
// cells: 0..n²-1 piyon kareleri (-1 boş, 0/1 piyon), sonra (n-1)² yatay ve
// (n-1)² dikey duvar yuvası (-1 boş, 0/1 sahibi). vars: [0] sonuç,
// [2]/[3] kalan duvar.

class WallRaceRules extends BoardRules<GridState> {
  final int n;
  const WallRaceRules(this.n);

  @override
  String get id => 'duvar-yarisi-$n';

  @override
  int get maxPly => 200;

  int get g => n - 1;
  int get hBase => n * n;
  int get vBase => n * n + g * g;
  int hIdx(int r, int c) => hBase + r * g + c;
  int vIdx(int r, int c) => vBase + r * g + c;

  @override
  GridState initial(SeededRandom rnd) {
    final s = GridState(n, n, List.filled(n * n + 2 * g * g, -1));
    s.cells[(n - 1) * n + n ~/ 2] = 0;
    s.cells[n ~/ 2] = 1;
    s.vars[2] = s.vars[3] = n == 9 ? 10 : (n == 7 ? 7 : 5);
    return s;
  }

  bool _h(GridState s, int r, int c) => r >= 0 && c >= 0 && r < g && c < g && s.cells[hIdx(r, c)] >= 0;
  bool _v(GridState s, int r, int c) => r >= 0 && c >= 0 && r < g && c < g && s.cells[vIdx(r, c)] >= 0;

  /// (r,c) karesinden (dr,dc) yönüne duvar var mı.
  bool blocked(GridState s, int r, int c, int dr, int dc) {
    if (dr == 1) return _h(s, r, c) || _h(s, r, c - 1);
    if (dr == -1) return _h(s, r - 1, c) || _h(s, r - 1, c - 1);
    if (dc == 1) return _v(s, r, c) || _v(s, r - 1, c);
    return _v(s, r, c - 1) || _v(s, r - 1, c - 1);
  }

  int pawn(GridState s, int p) {
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] == p) return i;
    }
    return -1;
  }

  int goalRow(int p) => p == 0 ? 0 : n - 1;

  /// Hedef sıraya en kısa yol (piyonlar yok sayılır); yol yoksa 999.
  int dist(GridState s, int p) {
    final start = pawn(s, p);
    if (start < 0) return 999;
    final d = List.filled(n * n, -1);
    d[start] = 0;
    final q = [start];
    for (var h = 0; h < q.length; h++) {
      final i = q[h];
      final r = i ~/ n, c = i % n;
      if (r == goalRow(p)) return d[i];
      for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        final nr = r + dr, nc = c + dc;
        if (nr < 0 || nc < 0 || nr >= n || nc >= n || blocked(s, r, c, dr, dc)) continue;
        final j = nr * n + nc;
        if (d[j] < 0) {
          d[j] = d[i] + 1;
          q.add(j);
        }
      }
    }
    return 999;
  }

  List<int> pawnMoves(GridState s) {
    final p = s.turn;
    final at = pawn(s, p);
    final r = at ~/ n, c = at % n;
    final out = <int>[];
    for (final (dr, dc) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final nr = r + dr, nc = c + dc;
      if (nr < 0 || nc < 0 || nr >= n || nc >= n || blocked(s, r, c, dr, dc)) continue;
      final t = nr * n + nc;
      if (s.cells[t] == -1) {
        out.add(mv(at, t));
        continue;
      }
      // Rakibin üstünden atla; arkası kapalıysa çaprazına geç.
      final jr = nr + dr, jc = nc + dc;
      if (jr >= 0 && jc >= 0 && jr < n && jc < n && !blocked(s, nr, nc, dr, dc)) {
        out.add(mv(at, jr * n + jc));
      } else {
        for (final (er, ec) in dr == 0 ? const [(1, 0), (-1, 0)] : const [(0, 1), (0, -1)]) {
          final sr = nr + er, sc = nc + ec;
          if (sr < 0 || sc < 0 || sr >= n || sc >= n || blocked(s, nr, nc, er, ec)) continue;
          out.add(mv(at, sr * n + sc));
        }
      }
    }
    return out;
  }

  bool wallFits(GridState s, int slot) {
    if (s.cells[slot] >= 0) return false;
    final horiz = slot < vBase;
    final k = slot - (horiz ? hBase : vBase);
    final r = k ~/ g, c = k % g;
    if (horiz) {
      if (_h(s, r, c - 1) || _h(s, r, c + 1) || _v(s, r, c)) return false;
    } else {
      if (_v(s, r - 1, c) || _v(s, r + 1, c) || _h(s, r, c)) return false;
    }
    s.cells[slot] = s.turn;
    final ok = dist(s, 0) < 999 && dist(s, 1) < 999;
    s.cells[slot] = -1;
    return ok;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final out = pawnMoves(s);
    if (s.vars[2 + s.turn] > 0) {
      for (var slot = hBase; slot < s.cells.length; slot++) {
        if (wallFits(s, slot)) out.add(mv(-1, slot));
      }
    }
    return out.isEmpty ? const [kPass] : out;
  }

  /// Aramada: piyon hamleleri ve rakibin en kısa yolunun yakınındaki duvarlar.
  @override
  List<int> searchMoves(GridState s) {
    final out = pawnMoves(s);
    if (s.vars[2 + s.turn] <= 0) return out.isEmpty ? const [kPass] : out;
    final o = pawn(s, 1 - s.turn);
    final orow = o ~/ n, ocol = o % n;
    final cand = <int>{};
    for (var r = orow - 2; r <= orow + 1; r++) {
      for (var c = ocol - 2; c <= ocol + 1; c++) {
        if (r < 0 || c < 0 || r >= g || c >= g) continue;
        cand.add(hIdx(r, c));
        cand.add(vIdx(r, c));
      }
    }
    final walls = [for (final slot in cand) if (wallFits(s, slot)) mv(-1, slot)];
    walls.sort((a, b) => moveOrder(s, b).compareTo(moveOrder(s, a)));
    return [...out, ...walls.take(10)];
  }

  @override
  int moveOrder(GridState s, int m) {
    if (m == kPass) return -99;
    final c = s.copy();
    apply(c, m);
    return (evaluate(c, s.turn) * 10).round();
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m != kPass) {
      if (mvFrom(m) >= 0) {
        s.cells[mvFrom(m)] = -1;
        s.cells[mvTo(m)] = p;
        if (mvTo(m) ~/ n == goalRow(p)) s.vars[0] = p + 1;
      } else {
        s.cells[mvTo(m)] = p;
        s.vars[2 + p]--;
      }
      s.last = mvTo(m);
    }
    s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  @override
  double evaluate(GridState s, int player) {
    final me = dist(s, player), op = dist(s, 1 - player);
    final tempo = s.turn == player ? 0.5 : 0;
    return ((op - me + tempo) * 8.0 + (s.vars[2 + player] - s.vars[3 - player]) * 1.2).clamp(-99, 99).toDouble();
  }

  @override
  String status(GridState s, String lang) => '▮ ${s.vars[2]} · ${s.vars[3]}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
