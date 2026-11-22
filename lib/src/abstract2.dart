import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';
import 'line_games.dart';

// ======================================================================
// Pente: beşli dizi ya da beş çift alım kazanır.
// vars[2], vars[3]: oyuncu 0/1'in aldığı çift sayısı.

class PenteRules extends LineRules {
  const PenteRules(int n) : super('pente', n, n, 5);

  static const _dirs = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)];

  int _captures(GridState s, int cell, int p, {bool apply = false}) {
    final c0 = cell % cols, r0 = cell ~/ cols;
    var n = 0;
    for (final (dc, dr) in _dirs) {
      final c3 = c0 + dc * 3, r3 = r0 + dr * 3;
      if (!s.inside(c3, r3)) continue;
      final a = (r0 + dr) * cols + c0 + dc, b = (r0 + dr * 2) * cols + c0 + dc * 2;
      if (s.cells[a] == 1 - p && s.cells[b] == 1 - p && s.cells[r3 * cols + c3] == p) {
        n++;
        if (apply) {
          s.cells[a] = -1;
          s.cells[b] = -1;
        }
      }
    }
    return n;
  }

  @override
  int moveOrder(GridState s, int m) => super.moveOrder(s, m) + _captures(s, mvTo(m), s.turn) * 400;

  @override
  void apply(GridState s, int m) {
    final cell = mvTo(m);
    final p = s.turn;
    s.cells[cell] = p;
    s.last = cell;
    s.ply++;
    s.vars[2 + p] += _captures(s, cell, p, apply: true);
    if (s.vars[2 + p] >= 5 || winsAt(s, cell, p)) {
      s.vars[0] = p + 1;
    } else if (!s.cells.contains(-1)) {
      s.vars[0] = 3;
    }
    s.turn = 1 - p;
  }

  @override
  double evaluate(GridState s, int player) =>
      (super.evaluate(s, player) + (s.vars[2 + player] - s.vars[3 - player]) * 9.0 + (s.vars[2 + player] >= 4 ? 15 : 0) - (s.vars[3 - player] >= 4 ? 18 : 0))
          .clamp(-99, 99)
          .toDouble();

  @override
  String status(GridState s, String lang) => '⚑ ${s.vars[2]} · ${s.vars[3]}';
}

// ======================================================================
// Altılı Bağ (Connect6): ilk hamlede bir, sonra her turda iki taş; altı
// taşı dizen kazanır. vars[1]: bu turda konan taş sayısı.

class Connect6Rules extends LineRules {
  const Connect6Rules(int n) : super('altili-bag', n, n, 6);

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
    s.vars[1]++;
    if (s.ply == 1 || s.vars[1] >= 2) {
      s.vars[1] = 0;
      s.turn = 1 - p;
    }
  }
}

// ======================================================================
// Halma ve Çin daması: taşları karşı köşedeki kampa taşıma yarışı.
// Hücre: -2 tahta dışı, -1 boş, 0/1 taş. Adım ya da zincirleme atlama.

class JumpRaceRules extends BoardRules<GridState> {
  /// true: yıldız tahta (Çin daması, 121 delik); false: kare Halma.
  final bool star;

  /// Kare tahtanın kenarı (8 ya da 10).
  final int n;
  const JumpRaceRules.halma(this.n) : star = false;
  const JumpRaceRules.star()
      : star = true,
        n = 17;

  @override
  String get id => star ? 'cin-damasi' : 'halma-$n';

  @override
  int get maxPly => star ? 360 : 300;

  @override
  double get decisive => 70;

  int get _camp => n == 8 ? 3 : 4;

  static const _sq = [(1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)];
  static const _hex = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];
  List<(int, int)> get dirs => star ? _hex : _sq;

  bool valid(int c, int r) {
    if (c < 0 || r < 0 || c >= n || r >= n) return false;
    if (!star) return true;
    final x = c - 8, z = r - 8, y = -x - z;
    final t1 = x <= 4 && y <= 4 && z <= 4;
    final t2 = x >= -4 && y >= -4 && z >= -4;
    return t1 || t2;
  }

  /// Oyuncunun başlangıç kampı.
  bool inCamp(int c, int r, int p) {
    if (star) {
      final z = r - 8;
      return p == 0 ? z >= 5 : z <= -5;
    }
    return p == 0 ? (n - 1 - c) + (n - 1 - r) <= _camp : c + r <= _camp;
  }

  bool inTarget(int c, int r, int p) => inCamp(c, r, 1 - p);

  /// Hedef kampın ucuna uzaklık.
  int dist(int c, int r, int p) {
    if (star) {
      // Uç noktalar: oyuncu 0 için (x=4, z=-8), oyuncu 1 için (x=-4, z=8).
      final tx = p == 0 ? 12 : 4, tz = p == 0 ? 0 : 16;
      final dq = c - tx, dr = r - tz;
      return (dq.abs() + dr.abs() + (dq + dr).abs()) ~/ 2;
    }
    return p == 0 ? (c > r ? c : r) : ((n - 1 - c) > (n - 1 - r) ? n - 1 - c : n - 1 - r);
  }

  @override
  GridState initial(SeededRandom rnd) {
    final s = GridState(n, n, List.filled(n * n, -2));
    for (var r = 0; r < n; r++) {
      for (var c = 0; c < n; c++) {
        if (!valid(c, r)) continue;
        s.cells[r * n + c] = inCamp(c, r, 0) ? 0 : (inCamp(c, r, 1) ? 1 : -1);
      }
    }
    return s;
  }

  Set<int> _reach(GridState s, int from) {
    final out = <int>{};
    final c0 = from % n, r0 = from ~/ n;
    for (final (dc, dr) in dirs) {
      final c = c0 + dc, r = r0 + dr;
      if (valid(c, r) && s.cells[r * n + c] == -1) out.add(r * n + c);
    }
    final seen = <int>{from};
    final stack = [from];
    while (stack.isNotEmpty) {
      final at = stack.removeLast();
      final ac = at % n, ar = at ~/ n;
      for (final (dc, dr) in dirs) {
        final mc = ac + dc, mr = ar + dr, lc = ac + 2 * dc, lr = ar + 2 * dr;
        if (!valid(lc, lr) || !valid(mc, mr)) continue;
        if (s.cells[mr * n + mc] < 0 || s.cells[lr * n + lc] != -1) continue;
        final land = lr * n + lc;
        if (seen.add(land)) {
          out.add(land);
          stack.add(land);
        }
      }
    }
    out.remove(from);
    return out;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] != p) continue;
      final home = inTarget(i % n, i ~/ n, p);
      for (final t in _reach(s, i)) {
        if (home && !inTarget(t % n, t ~/ n, p)) continue; // hedefe varan çıkmaz
        out.add(mv(i, t));
      }
    }
    return out.isEmpty ? const [kPass] : out;
  }

  @override
  int moveOrder(GridState s, int m) {
    if (m == kPass) return -99;
    final f = mvFrom(m), t = mvTo(m), p = s.turn;
    return dist(f % n, f ~/ n, p) - dist(t % n, t ~/ n, p);
  }

  @override
  List<int> searchMoves(GridState s) {
    final ms = moves(s)..sort((a, b) => moveOrder(s, b).compareTo(moveOrder(s, a)));
    return ms.length > 12 ? ms.sublist(0, 12) : ms;
  }

  /// Bütün taşlar hedefte ya da hedef dolu ve en az yarısı oyuncunun
  /// (rakip kampından çıkmayarak oyunu kilitleyemez).
  bool _done(GridState s, int p) {
    var mine = 0, full = true, all = 0, size = 0;
    for (var i = 0; i < s.cells.length; i++) {
      final c = i % n, r = i ~/ n;
      if (s.cells[i] == p) all++;
      if (!valid(c, r) || !inTarget(c, r, p)) continue;
      size++;
      final v = s.cells[i];
      if (v == p) mine++;
      if (v < 0) full = false;
    }
    return mine == all || (full && mine * 2 >= size);
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m != kPass) {
      s.cells[mvTo(m)] = p;
      s.cells[mvFrom(m)] = -1;
      s.last = mvTo(m);
    }
    if (_done(s, p)) s.vars[0] = p + 1;
    s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  @override
  double evaluate(GridState s, int player) {
    var a = 0, b = 0;
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (v < 0) continue;
      final d = dist(i % n, i ~/ n, v);
      if (v == player) {
        a += d * d;
      } else {
        b += d * d;
      }
    }
    return ((b - a) / (star ? 6.0 : 4.0)).clamp(-99, 99).toDouble();
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Alquerque: 5×5 noktalı tahta; çapraz çizgiler (satır+sütun çift olan
// noktalarda). Taş ileri ya da yana adım atar; atlayarak alır, alma
// zorunlu ve zincirlemedir. vars[1]: alımsız hamle sayacı.

class AlquerqueRules extends BoardRules<GridState> {
  const AlquerqueRules();

  @override
  String get id => 'alquerque';

  @override
  int get maxPly => 200;

  @override
  double get decisive => 45;

  static const n = 5;

  static List<(int, int)> lines(int i) {
    final c = i % n, r = i ~/ n;
    return [(1, 0), (-1, 0), (0, 1), (0, -1), if ((r + c).isEven) ...[(1, 1), (-1, -1), (1, -1), (-1, 1)]];
  }

  static bool _in(int c, int r) => c >= 0 && r >= 0 && c < n && r < n;

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(25, -1);
    for (var i = 0; i < 25; i++) {
      final c = i % n, r = i ~/ n;
      if (r < 2 || (r == 2 && c < 2)) cells[i] = 1;
      if (r > 2 || (r == 2 && c > 2)) cells[i] = 0;
    }
    return GridState(n, n, cells);
  }

  int fwd(int p) => p == 0 ? -1 : 1;

  List<(int, List<int>)> _caps(GridState s, int from) {
    final p = s.cells[from];
    final out = <(int, List<int>)>[];
    void dfs(int at, List<int> taken) {
      var any = false;
      for (final (dc, dr) in lines(at)) {
        final mc = at % n + dc, mr = at ~/ n + dr, lc = at % n + 2 * dc, lr = at ~/ n + 2 * dr;
        if (!_in(lc, lr)) continue;
        final mid = mr * n + mc, land = lr * n + lc;
        if (s.cells[mid] != 1 - p || taken.contains(mid)) continue;
        if (s.cells[land] != -1 && land != from) continue;
        any = true;
        dfs(land, [...taken, mid]);
      }
      if (!any && taken.isNotEmpty) out.add((at, taken));
    }

    dfs(from, const []);
    return out;
  }

  List<(int, List<int>)> _all(GridState s) {
    final p = s.turn;
    final caps = <(int, List<int>)>[];
    final seen = <int, int>{};
    for (var i = 0; i < 25; i++) {
      if (s.cells[i] != p) continue;
      for (final (e, t) in _caps(s, i)) {
        caps.add((mv(i, e, seen.update(i * 64 + e, (x) => x + 1, ifAbsent: () => 0)), t));
      }
    }
    if (caps.isNotEmpty) return caps;
    final out = <(int, List<int>)>[];
    for (var i = 0; i < 25; i++) {
      if (s.cells[i] != p) continue;
      for (final (dc, dr) in lines(i)) {
        if (dr == -fwd(p)) continue; // geri gidilmez
        final c = i % n + dc, r = i ~/ n + dr;
        if (_in(c, r) && s.cells[r * n + c] == -1) out.add((mv(i, r * n + c), const []));
      }
    }
    return out;
  }

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : [for (final x in _all(s)) x.$1];

  @override
  int moveOrder(GridState s, int m) {
    for (final (code, t) in _all(s)) {
      if (code == m) return t.length;
    }
    return 0;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    var taken = const <int>[];
    for (final (code, t) in _all(s)) {
      if (code == m) {
        taken = t;
        break;
      }
    }
    s.cells[mvFrom(m)] = -1;
    for (final t in taken) {
      s.cells[t] = -1;
    }
    s.cells[mvTo(m)] = p;
    s.last = mvTo(m);
    s.ply++;
    s.vars[1] = taken.isEmpty ? s.vars[1] + 1 : 0;
    s.turn = 1 - p;
    if (s.vars[1] >= 40 || _all(s).isEmpty) s.vars[0] = 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) {
    if (!isOver(s)) return -1;
    if (s.vars[1] >= 40) {
      final a = s.cells.where((x) => x == 0).length, b = s.cells.where((x) => x == 1).length;
      return a == b ? -1 : (a > b ? 0 : 1);
    }
    return 1 - s.turn;
  }

  @override
  double evaluate(GridState s, int player) {
    var v = 0.0;
    for (var i = 0; i < 25; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      final adv = x == 0 ? 4 - i ~/ n : i ~/ n;
      final val = 10 + adv * 0.4 + (lines(i).length > 4 ? 0.6 : 0);
      v += x == player ? val : -val;
    }
    return v.clamp(-99, 99).toDouble();
  }

  @override
  String status(GridState s, String lang) => '● ${s.cells.where((x) => x == 0).length} · ${s.cells.where((x) => x == 1).length}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Surakarta: 6×6; taş bir kare yürür, alım yalnızca köşe halkalarından en
// az birinden geçerek, yolu açık bir devre boyunca yapılır.
// vars[1]: alımsız hamle sayacı.

class SurakartaRules extends BoardRules<GridState> {
  const SurakartaRules();

  @override
  String get id => 'surakarta';

  @override
  int get maxPly => 240;

  @override
  double get decisive => 50;

  static const n = 6;

  /// İki devre: her biri 24 noktalık sıra ve bölüm sonlarında halka.
  static final List<List<int>> circuits = [_circuit(1), _circuit(2)];

  static List<int> _circuit(int k) {
    final a = k, b = n - 1 - k;
    return [
      for (var c = 0; c < n; c++) a * n + c, // satır a, soldan sağa
      for (var r = 0; r < n; r++) r * n + b, // sütun b, yukarıdan aşağı
      for (var c = n - 1; c >= 0; c--) b * n + c, // satır b, sağdan sola
      for (var r = n - 1; r >= 0; r--) r * n + a, // sütun a, aşağıdan yukarı
    ];
  }

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(36, -1);
    for (var i = 0; i < 36; i++) {
      if (i ~/ n < 2) cells[i] = 1;
      if (i ~/ n >= 4) cells[i] = 0;
    }
    return GridState(n, n, cells);
  }

  /// Bir taşın devreler üzerinden yapabileceği alımlar.
  Set<int> _attacks(GridState s, int from) {
    final p = s.cells[from];
    final out = <int>{};
    for (final circ in circuits) {
      for (var i = 0; i < circ.length; i++) {
        if (circ[i] != from) continue;
        for (final step in const [1, -1]) {
          var loop = false;
          var j = i;
          for (var k = 0; k < circ.length; k++) {
            final next = (j + step + circ.length) % circ.length;
            // Bölüm sınırı geçilirse halkadan geçilmiş olur.
            if ((step == 1 && next % n == 0) || (step == -1 && j % n == 0)) loop = true;
            j = next;
            final cell = circ[j];
            if (cell == from) continue;
            final v = s.cells[cell];
            if (v < 0) continue;
            if (v == p) break;
            if (loop) out.add(cell);
            break;
          }
        }
      }
    }
    return out;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    for (var i = 0; i < 36; i++) {
      if (s.cells[i] != p) continue;
      for (final t in _attacks(s, i)) {
        out.add(mv(i, t, 1));
      }
      final c0 = i % n, r0 = i ~/ n;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          if (dr == 0 && dc == 0) continue;
          final c = c0 + dc, r = r0 + dr;
          if (c >= 0 && r >= 0 && c < n && r < n && s.cells[r * n + c] == -1) out.add(mv(i, r * n + c));
        }
      }
    }
    return out.isEmpty ? const [kPass] : out;
  }

  @override
  int moveOrder(GridState s, int m) => m == kPass ? -1 : mvExtra(m) * 10;

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m != kPass) {
      final cap = s.cells[mvTo(m)] >= 0;
      s.cells[mvTo(m)] = p;
      s.cells[mvFrom(m)] = -1;
      s.last = mvTo(m);
      s.vars[1] = cap ? 0 : s.vars[1] + 1;
    } else {
      s.vars[1]++;
    }
    s.turn = 1 - p;
    final a = s.cells.where((x) => x == 0).length, b = s.cells.where((x) => x == 1).length;
    if (a == 0 || b == 0 || s.vars[1] >= 50) s.vars[0] = 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) {
    if (!isOver(s)) return -1;
    final a = s.cells.where((x) => x == 0).length, b = s.cells.where((x) => x == 1).length;
    return a == b ? -1 : (a > b ? 0 : 1);
  }

  @override
  double evaluate(GridState s, int player) {
    var v = 0.0;
    for (var i = 0; i < 36; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      v += x == player ? 10 : -10;
    }
    // Tehdit altındaki taşlar.
    for (var i = 0; i < 36; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      final threats = _attacks(s, i).length;
      v += x == player ? threats * 1.5 : -threats * 1.5;
    }
    return v.clamp(-99, 99).toDouble();
  }

  @override
  String status(GridState s, String lang) => '● ${s.cells.where((x) => x == 0).length} · ${s.cells.where((x) => x == 1).length}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Tafl (Hnefatafl ailesi): saldıranlar (0) ortadaki kralı yakalamaya,
// savunanlar (1) kralı bir köşeye kaçırmaya çalışır. Hücre: -1 boş,
// 0 saldıran, 1 savunan, 2 kral. Taşlar kale gibi düz gider.

class TaflRules extends BoardRules<GridState> {
  final int n;
  const TaflRules(this.n);

  @override
  String get id => 'tafl-$n';

  @override
  int get maxPly => n == 7 ? 160 : (n == 9 ? 220 : 280);

  @override
  double get decisive => 60;

  int get center => (n ~/ 2) * n + n ~/ 2;
  bool corner(int i) => i == 0 || i == n - 1 || i == n * (n - 1) || i == n * n - 1;
  bool restricted(int i) => corner(i) || i == center;
  int owner(int v) => v < 0 ? -1 : (v == 0 ? 0 : 1);

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(n * n, -1);
    void put(int r, int c, int v) => cells[r * n + c] = v;
    final m = n ~/ 2;
    put(m, m, 2);
    if (n == 7) {
      for (final d in const [1]) {
        put(m - d, m, 1);
        put(m + d, m, 1);
        put(m, m - d, 1);
        put(m, m + d, 1);
      }
      for (final d in const [2, 3]) {
        put(m - d, m, 0);
        put(m + d, m, 0);
        put(m, m - d, 0);
        put(m, m + d, 0);
      }
    } else if (n == 9) {
      for (final d in const [1, 2]) {
        put(m - d, m, 1);
        put(m + d, m, 1);
        put(m, m - d, 1);
        put(m, m + d, 1);
      }
      for (var k = -1; k <= 1; k++) {
        put(0, m + k, 0);
        put(n - 1, m + k, 0);
        put(m + k, 0, 0);
        put(m + k, n - 1, 0);
      }
      put(1, m, 0);
      put(n - 2, m, 0);
      put(m, 1, 0);
      put(m, n - 2, 0);
    } else {
      // 11×11
      for (final (r, c) in const [(3, 5), (4, 4), (4, 5), (4, 6), (5, 3), (5, 4), (5, 6), (5, 7), (6, 4), (6, 5), (6, 6), (7, 5)]) {
        put(r, c, 1);
      }
      for (var k = 3; k <= 7; k++) {
        put(0, k, 0);
        put(n - 1, k, 0);
        put(k, 0, 0);
        put(k, n - 1, 0);
      }
      put(1, 5, 0);
      put(n - 2, 5, 0);
      put(5, 1, 0);
      put(5, n - 2, 0);
    }
    return GridState(n, n, cells);
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (owner(v) != p) continue;
      final king = v == 2;
      for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
        var c = i % n + dc, r = i ~/ n + dr;
        while (c >= 0 && r >= 0 && c < n && r < n) {
          final t = r * n + c;
          if (s.cells[t] != -1) break;
          if (restricted(t) && !king) break;
          out.add(mv(i, t));
          c += dc;
          r += dr;
        }
      }
    }
    return out.isEmpty ? const [kPass] : out;
  }

  bool _hostileFor(GridState s, int cell, int victimOwner) {
    final v = s.cells[cell];
    if (v >= 0) return owner(v) != victimOwner;
    return corner(cell) || (cell == center && v == -1);
  }

  bool _nearThrone(int i) {
    final c = i % n, r = i ~/ n, m = n ~/ 2;
    return (c - m).abs() + (r - m).abs() <= 1;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m == kPass) {
      s.turn = 1 - p;
      return;
    }
    final from = mvFrom(m), to = mvTo(m);
    final moved = s.cells[from];
    s.cells[from] = -1;
    s.cells[to] = moved;
    s.last = to;
    if (moved == 2 && corner(to)) {
      s.vars[0] = 2; // savunan kazandı
      s.turn = 1 - p;
      return;
    }
    final c0 = to % n, r0 = to ~/ n;
    for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final c1 = c0 + dc, r1 = r0 + dr, c2 = c0 + 2 * dc, r2 = r0 + 2 * dr;
      if (c1 < 0 || r1 < 0 || c1 >= n || r1 >= n) continue;
      final y = r1 * n + c1;
      final vy = s.cells[y];
      if (vy < 0 || owner(vy) == p) continue;
      if (vy == 2) {
        // Kral: 7×7'de tahtın uzağında iki yandan, diğerlerinde dört yandan.
        if (n == 7 && !_nearThrone(y)) {
          if (c2 >= 0 && r2 >= 0 && c2 < n && r2 < n && (s.cells[r2 * n + c2] == 0 || corner(r2 * n + c2))) s.vars[0] = 1;
        } else {
          var surrounded = true;
          for (final (ec, er) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            final cc = c1 + ec, rr = r1 + er;
            if (cc < 0 || rr < 0 || cc >= n || rr >= n) {
              surrounded = false;
              break;
            }
            final z = rr * n + cc;
            if (!(s.cells[z] == 0 || (z == center && s.cells[z] == -1))) {
              surrounded = false;
              break;
            }
          }
          if (surrounded) s.vars[0] = 1;
        }
        continue;
      }
      if (c2 < 0 || r2 < 0 || c2 >= n || r2 >= n) continue;
      if (_hostileFor(s, r2 * n + c2, owner(vy))) s.cells[y] = -1;
    }
    s.turn = 1 - p;
    if (s.vars[0] == 0 && moves(s).first == kPass) s.vars[0] = 2 - s.turn; // hamlesi kalmayan kaybeder
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  int kingCell(GridState s) => s.cells.indexOf(2);

  @override
  double evaluate(GridState s, int player) {
    final k = kingCell(s);
    if (k < 0) return player == 0 ? 99 : -99;
    var att = 0, def = 0;
    for (final v in s.cells) {
      if (v == 0) att++;
      if (v == 1) def++;
    }
    final kc = k % n, kr = k ~/ n;
    // Kralın köşeye açık yolları.
    var open = 0;
    for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      var c = kc + dc, r = kr + dr;
      var clear = true;
      while (c >= 0 && r >= 0 && c < n && r < n) {
        if (s.cells[r * n + c] != -1) {
          clear = false;
          break;
        }
        c += dc;
        r += dr;
      }
      final ec = c - dc, er = r - dr;
      if (clear && (ec == 0 || ec == n - 1) && (er == 0 || er == n - 1)) open += 3;
      if (clear) open++;
    }
    var around = 0;
    for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
      final c = kc + dc, r = kr + dr;
      if (c >= 0 && r >= 0 && c < n && r < n && s.cells[r * n + c] == 0) around++;
    }
    final edge = [kc, kr, n - 1 - kc, n - 1 - kr].reduce((a, b) => a < b ? a : b);
    final defV = def * 3.0 - att * 1.6 + open * 9 - around * 6 - edge * 1.5;
    return (player == 1 ? defV : -defV).clamp(-99, 99).toDouble();
  }

  @override
  int moveOrder(GridState s, int m) {
    if (m == kPass) return -9;
    final t = mvTo(m);
    if (s.cells[mvFrom(m)] == 2) return corner(t) ? 1000 : 20;
    return 0;
  }

  @override
  List<int> searchMoves(GridState s) {
    final ms = moves(s);
    if (ms.length <= 28) return ms;
    ms.sort((a, b) => moveOrder(s, b).compareTo(moveOrder(s, a)));
    final k = kingCell(s);
    final kc = k % n, kr = k ~/ n;
    int near(int m) {
      final t = mvTo(m);
      return -((t % n - kc).abs() + (t ~/ n - kr).abs());
    }

    final rest = ms.sublist(4)..sort((a, b) => near(b).compareTo(near(a)));
    return [...ms.take(4), ...rest.take(24)];
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Havannah: altıgen tahtada halka, köprü (iki köşe) ya da çatal (üç kenar)
// kuran kazanır. Izgara (2n-1)², tahta dışı hücreler -2.

class HavannahRules extends BoardRules<GridState> {
  /// Kenar uzunluğu.
  final int side;
  const HavannahRules(this.side);

  @override
  String get id => 'havannah-$side';

  int get w => 2 * side - 1;

  @override
  int get maxPly => w * w;

  bool valid(int q, int r) {
    final m = side - 1;
    final x = q - m, z = r - m, y = -x - z;
    return x.abs() <= m && z.abs() <= m && y.abs() <= m;
  }

  static const dirs = [(1, 0), (1, -1), (0, -1), (-1, 0), (-1, 1), (0, 1)];

  @override
  GridState initial(SeededRandom rnd) {
    final cells = List.filled(w * w, -2);
    for (var r = 0; r < w; r++) {
      for (var q = 0; q < w; q++) {
        if (valid(q, r)) cells[r * w + q] = -1;
      }
    }
    return GridState(w, w, cells);
  }

  List<int> neighbors(int i) {
    final q = i % w, r = i ~/ w;
    return [
      for (final (dq, dr) in dirs)
        if (q + dq >= 0 && r + dr >= 0 && q + dq < w && r + dr < w && valid(q + dq, r + dr)) (r + dr) * w + q + dq,
    ];
  }

  /// Köşe kimliği (0..5) ya da -1; kenar kimliği (0..5) ya da -1.
  (int, int) cornerEdge(int i) {
    final m = side - 1;
    final x = i % w - m, z = i ~/ w - m, y = -x - z;
    final onX = x.abs() == m, onY = y.abs() == m, onZ = z.abs() == m;
    final k = (onX ? 1 : 0) + (onY ? 1 : 0) + (onZ ? 1 : 0);
    if (k >= 2) {
      final id = x == m ? (z == -m ? 0 : 1) : (x == -m ? (z == m ? 3 : 4) : (z == m ? 2 : 5));
      return (id, -1);
    }
    if (k == 1) {
      if (onX) return (-1, x > 0 ? 0 : 3);
      if (onY) return (-1, y > 0 ? 1 : 4);
      return (-1, z > 0 ? 2 : 5);
    }
    return (-1, -1);
  }

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : [for (var i = 0; i < s.cells.length; i++) if (s.cells[i] == -1) mv(-1, i)];

  @override
  List<int> searchMoves(GridState s) {
    var any = false;
    final near = <int>{};
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] < 0) continue;
      any = true;
      for (final a in neighbors(i)) {
        if (s.cells[a] == -1) near.add(a);
        for (final b in neighbors(a)) {
          if (s.cells[b] == -1) near.add(b);
        }
      }
    }
    if (!any) return [mv(-1, (w ~/ 2) * w + w ~/ 2)];
    final ms = [for (final i in near) mv(-1, i)]..sort((a, b) => moveOrder(s, b).compareTo(moveOrder(s, a)));
    return ms.length > 16 ? ms.sublist(0, 16) : ms;
  }

  @override
  int moveOrder(GridState s, int m) {
    final i = mvTo(m);
    var v = 0;
    for (final a in neighbors(i)) {
      if (s.cells[a] == s.turn) v += 3;
      if (s.cells[a] == 1 - s.turn) v += 2;
    }
    final (c, e) = cornerEdge(i);
    if (c >= 0) v += 2;
    if (e >= 0) v += 1;
    return v;
  }

  Set<int> group(GridState s, int from) {
    final p = s.cells[from];
    final seen = <int>{from};
    final stack = [from];
    while (stack.isNotEmpty) {
      for (final a in neighbors(stack.removeLast())) {
        if (s.cells[a] == p && seen.add(a)) stack.add(a);
      }
    }
    return seen;
  }

  bool _ring(GridState s, Set<int> g) {
    for (final i in g) {
      final ns = neighbors(i);
      if (ns.length == 6 && ns.every(g.contains)) return true;
    }
    final reached = <int>{};
    final stack = <int>[];
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] == -2 || g.contains(i)) continue;
      if (neighbors(i).length < 6 && reached.add(i)) stack.add(i);
    }
    while (stack.isNotEmpty) {
      for (final a in neighbors(stack.removeLast())) {
        if (!g.contains(a) && reached.add(a)) stack.add(a);
      }
    }
    for (var i = 0; i < s.cells.length; i++) {
      if (s.cells[i] != -2 && !g.contains(i) && !reached.contains(i)) return true;
    }
    return false;
  }

  bool winsWith(GridState s, int cell) {
    final g = group(s, cell);
    final corners = <int>{}, edges = <int>{};
    for (final i in g) {
      final (c, e) = cornerEdge(i);
      if (c >= 0) corners.add(c);
      if (e >= 0) edges.add(e);
    }
    if (corners.length >= 2 || edges.length >= 3) return true;
    return g.length >= 6 && _ring(s, g);
  }

  @override
  void apply(GridState s, int m) {
    final cell = mvTo(m);
    final p = s.turn;
    s.cells[cell] = p;
    s.last = cell;
    s.ply++;
    if (winsWith(s, cell)) {
      s.vars[0] = p + 1;
    } else if (!s.cells.contains(-1)) {
      s.vars[0] = 3;
    }
    s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 1 ? 0 : (s.vars[0] == 2 ? 1 : -1);

  @override
  double evaluate(GridState s, int player) {
    double score(int p) {
      final seen = <int>{};
      var best = 0.0;
      for (var i = 0; i < s.cells.length; i++) {
        if (s.cells[i] != p || seen.contains(i)) continue;
        final g = group(s, i);
        seen.addAll(g);
        final corners = <int>{}, edges = <int>{};
        for (final x in g) {
          final (c, e) = cornerEdge(x);
          if (c >= 0) corners.add(c);
          if (e >= 0) edges.add(e);
        }
        final v = corners.length * 9.0 + edges.length * 7.0 + g.length * 0.6;
        if (v > best) best = v;
      }
      return best;
    }

    return (score(player) - score(1 - player) * 1.1).clamp(-99, 99).toDouble();
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
