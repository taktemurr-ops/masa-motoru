import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

// ---------------------------------------------------------------- Hex

/// Hex: eşkenar dörtgen tahta. Oyuncu 0 üst ve alt kenarı, oyuncu 1 sol ve
/// sağ kenarı birleştirmeye çalışır. Beraberlik yoktur. vars[0]: kazanan+1.
class HexRules extends BoardRules<GridState> {
  final int n;
  const HexRules([this.n = 11]);

  @override
  String get id => 'hex';

  @override
  int get maxPly => n * n + 1;

  static const _nb = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, -1), (-1, 1)];

  @override
  GridState initial(SeededRandom r) => GridState(n, n, List.filled(n * n, -1));

  @override
  List<int> moves(GridState s) =>
      isOver(s) ? const [] : [for (var i = 0; i < s.cells.length; i++) if (s.cells[i] < 0) mv(-1, i)];

  @override
  List<int> searchMoves(GridState s) {
    if (s.ply == 0) return [mv(-1, (n ~/ 2) * n + n ~/ 2)];
    final near = <int>{};
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] < 0) continue;
      final c = i % n, r = i ~/ n;
      for (final (dc, dr) in _nb) {
        for (final k in const [1, 2]) {
          final nc = c + dc * k, nr = r + dr * k;
          if (s.inside(nc, nr) && s.cells[nr * n + nc] < 0) near.add(nr * n + nc);
        }
      }
    }
    final path = <int>{..._pathCells(s, 0), ..._pathCells(s, 1)};
    final ms = [for (final i in {...near, ...path}) mv(-1, i)]
      ..sort((a, b) => _order(s, mvTo(b), path).compareTo(_order(s, mvTo(a), path)));
    return ms.length > 16 ? ms.sublist(0, 16) : ms;
  }

  int _order(GridState s, int i, Set<int> path) {
    var v = path.contains(i) ? 10 : 0;
    final c = i % n, r = i ~/ n;
    for (final (dc, dr) in _nb) {
      if (s.inside(c + dc, r + dr) && s.cells[(r + dr) * n + c + dc] >= 0) v += 2;
    }
    return v;
  }

  @override
  void apply(GridState s, int m) {
    final cell = mvTo(m);
    final p = s.turn;
    s.cells[cell] = p;
    s.last = cell;
    s.ply++;
    if (_dist(s, p) == 0) s.vars[0] = p + 1;
    s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  /// 0-1 BFS: kendi taşı 0, boş 1, rakip geçilmez. Kenardan kenara mesafe.
  int _dist(GridState s, int p) => _bfs(s, p).$1;

  (int, List<int>, List<int>) _bfs(GridState s, int p) {
    const inf = 1 << 20;
    final d = List<int>.filled(n * n, inf);
    final prev = List<int>.filled(n * n, -1);
    final dq = <int>[];
    var head = 0;
    void push(int i, int w, int from) {
      final v = s.cells[i];
      if (v == 1 - p) return;
      final cost = w + (v == p ? 0 : 1);
      if (cost < d[i]) {
        d[i] = cost;
        prev[i] = from;
        dq.add(i);
      }
    }

    for (var k = 0; k < n; k++) {
      push(p == 0 ? k : k * n, 0, -1);
    }
    var iter = 0;
    while (head < dq.length && iter++ < 20000) {
      final i = dq[head++];
      final c = i % n, r = i ~/ n;
      for (final (dc, dr) in _nb) {
        final nc = c + dc, nr = r + dr;
        if (nc < 0 || nr < 0 || nc >= n || nr >= n) continue;
        push(nr * n + nc, d[i], i);
      }
    }
    var best = inf, end = -1;
    for (var k = 0; k < n; k++) {
      final i = p == 0 ? (n - 1) * n + k : k * n + n - 1;
      if (d[i] < best) {
        best = d[i];
        end = i;
      }
    }
    return (best, d, [end, ...prev]);
  }

  List<int> _pathCells(GridState s, int p) {
    final (_, _, ep) = _bfs(s, p);
    final end = ep.first;
    final prev = ep.sublist(1);
    final out = <int>[];
    var i = end, guard = 0;
    while (i >= 0 && guard++ < n * n) {
      if (s.cells[i] < 0) out.add(i);
      i = prev[i];
    }
    return out;
  }

  @override
  double evaluate(GridState s, int player) {
    final me = _dist(s, player), them = _dist(s, 1 - player);
    if (me >= 1 << 20) return -90;
    if (them >= 1 << 20) return 90;
    return ((them - me) * 8.0 + (s.turn == player ? 3 : -3)).clamp(-90, 90).toDouble();
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ---------------------------------------------------------------- Noktalar ve kutular

/// Noktalar ve kutular: sırayla iki nokta arasına çizgi çek. Kutunun dördüncü
/// kenarını çizen kutuyu alır ve bir daha oynar. Çok kutu alan kazanır.
/// cells: önce kenarlar (-1 boş, 0/1 çizen), sonra kutular (-1 / sahibi).
/// vars[0]: bitti (1), vars[1..2]: skorlar.
class DotsRules extends BoardRules<GridState> {
  final int w, h;
  const DotsRules(this.w, this.h);

  @override
  String get id => 'dots';

  int get hCount => w * (h + 1);
  int get vCount => (w + 1) * h;
  int get edges => hCount + vCount;

  int hEdge(int c, int r) => r * w + c;
  int vEdge(int c, int r) => hCount + r * (w + 1) + c;
  List<int> boxEdges(int c, int r) => [hEdge(c, r), hEdge(c, r + 1), vEdge(c, r), vEdge(c + 1, r)];

  /// Kenarın komşu kutuları (1 ya da 2).
  List<int> edgeBoxes(int e) {
    if (e < hCount) {
      final c = e % w, r = e ~/ w;
      return [if (r > 0) (r - 1) * w + c, if (r < h) r * w + c];
    }
    final x = e - hCount;
    final c = x % (w + 1), r = x ~/ (w + 1);
    return [if (c > 0) r * w + c - 1, if (c < w) r * w + c];
  }

  int sides(GridState s, int box) {
    final c = box % w, r = box ~/ w;
    return boxEdges(c, r).where((e) => s.cells[e] >= 0).length;
  }

  @override
  int get maxPly => edges + 1;

  @override
  GridState initial(SeededRandom r) => GridState(w, h, List.filled(edges + w * h, -1));

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : [for (var e = 0; e < edges; e++) if (s.cells[e] < 0) mv(-1, e)];

  @override
  void apply(GridState s, int m) {
    final e = mvTo(m);
    final p = s.turn;
    s.cells[e] = p;
    s.last = e;
    s.ply++;
    var made = 0;
    for (final b in edgeBoxes(e)) {
      if (sides(s, b) == 4 && s.cells[edges + b] < 0) {
        s.cells[edges + b] = p;
        s.vars[1 + p]++;
        made++;
      }
    }
    if (made == 0) s.turn = 1 - p;
    if (s.vars[1] + s.vars[2] == w * h) s.vars[0] = 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) => s.vars[1] == s.vars[2] ? -1 : (s.vars[1] > s.vars[2] ? 0 : 1);

  @override
  int moveOrder(GridState s, int m) {
    final e = mvTo(m);
    var v = 0;
    for (final b in edgeBoxes(e)) {
      final k = sides(s, b);
      if (k == 3) v += 100;
      if (k == 2) v -= 40;
    }
    return v;
  }

  @override
  double evaluate(GridState s, int player) {
    final diff = s.vars[1 + player] - s.vars[2 - player];
    var three = 0;
    for (var b = 0; b < w * h; b++) {
      if (s.cells[edges + b] < 0 && sides(s, b) == 3) three++;
    }
    return diff * 10.0 + (s.turn == player ? three : -three) * 7.0;
  }

  @override
  String status(GridState s, String lang) => '${s.vars[1]} : ${s.vars[2]}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
