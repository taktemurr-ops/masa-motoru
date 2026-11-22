import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Dama kuralları ailesi: İngiliz, Rus, Brezilya, Pool, Uluslararası (10×10),
/// Türk daması (dikey/yatay). Hücre: -1 boş, 0/1 taş, 2/3 dama (kral).
/// vars[0]: bitti (1), vars[1]: alımsız hamle sayacı.
class DraughtsRules extends BoardRules<GridState> {
  @override
  final String id;
  final int n;
  final int rowsOfMen;

  /// Türk daması: düz (dikey/yatay) yürür, bütün kareler kullanılır.
  final bool orthogonal;

  /// Taş geriye doğru alabilir mi.
  final bool menCaptureBack;

  /// Dama uzun gider mi (uçan dama).
  final bool flyingKings;

  /// En çok taş alan yol zorunlu mu.
  final bool maxCapture;

  /// Alım sırasında son sıraya varan taş dama olup devam eder mi (Rus).
  final bool promoteMidCapture;

  /// Taş son sıraya varınca alım biter mi (İngiliz).
  final bool stopOnPromote;

  /// Taş damayı alabilir mi (İtalyan: alamaz).
  final bool menCaptureKings;

  /// Dama ile alım varsa önce o yapılır (İtalyan, Çek).
  final bool kingFirst;

  /// Eşit alımlarda en çok dama alan yol seçilir (İtalyan, İspanyol).
  final bool maxKingsTaken;

  const DraughtsRules({
    required this.id,
    this.n = 8,
    this.rowsOfMen = 3,
    this.orthogonal = false,
    this.menCaptureBack = true,
    this.flyingKings = true,
    this.maxCapture = false,
    this.promoteMidCapture = false,
    this.stopOnPromote = false,
    this.menCaptureKings = true,
    this.kingFirst = false,
    this.maxKingsTaken = false,
  });

  static const english = DraughtsRules(id: 'dama', menCaptureBack: false, flyingKings: false, stopOnPromote: true);
  static const turkish = DraughtsRules(id: 'turk-damasi', orthogonal: true, rowsOfMen: 2, maxCapture: true);
  static const russian = DraughtsRules(id: 'rus-damasi', promoteMidCapture: true);
  static const brazilian = DraughtsRules(id: 'brezilya-damasi', maxCapture: true);
  static const pool = DraughtsRules(id: 'pool-damasi');
  static const international = DraughtsRules(id: 'uluslararasi-dama', n: 10, rowsOfMen: 4, maxCapture: true);
  static const italian = DraughtsRules(id: 'italyan-damasi', menCaptureBack: false, flyingKings: false, menCaptureKings: false, maxCapture: true, kingFirst: true, maxKingsTaken: true);
  static const spanish = DraughtsRules(id: 'ispanyol-damasi', menCaptureBack: false, maxCapture: true, maxKingsTaken: true);
  static const czech = DraughtsRules(id: 'cek-damasi', menCaptureBack: false, kingFirst: true);
  static const canadian = DraughtsRules(id: 'kanada-damasi', n: 12, rowsOfMen: 5, maxCapture: true);

  @override
  int get maxPly => 260;

  @override
  double get decisive => 55;

  bool playable(int c, int r) => orthogonal || (r + c) % 2 == 1;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(n, n, List.filled(n * n, -1));
    for (var row = 0; row < n; row++) {
      for (var c = 0; c < n; c++) {
        if (!playable(c, row)) continue;
        if (orthogonal) {
          if (row == 1 || row == 2) s.cells[row * n + c] = 1;
          if (row == n - 2 || row == n - 3) s.cells[row * n + c] = 0;
        } else {
          if (row < rowsOfMen) s.cells[row * n + c] = 1;
          if (row >= n - rowsOfMen) s.cells[row * n + c] = 0;
        }
      }
    }
    return s;
  }

  int owner(int v) => v < 0 ? -1 : v % 2;
  bool king(int v) => v >= 2;
  int fwd(int p) => p == 0 ? -1 : 1;
  int promoRow(int p) => p == 0 ? 0 : n - 1;

  List<(int, int)> _dirs(int p, bool k, bool capture) {
    if (orthogonal) {
      if (k) return const [(1, 0), (-1, 0), (0, 1), (0, -1)];
      return [(1, 0), (-1, 0), (0, fwd(p))];
    }
    if (k || (capture && menCaptureBack)) return const [(1, 1), (1, -1), (-1, 1), (-1, -1)];
    return [(1, fwd(p)), (-1, fwd(p))];
  }

  bool _in(int c, int r) => c >= 0 && r >= 0 && c < n && r < n;

  /// Alım dizileri: (bitiş, alınan kareler).
  List<(int, List<int>, bool)> _captures(GridState s, int from) {
    final v = s.cells[from];
    final p = owner(v);
    final out = <(int, List<int>, bool)>[];
    final cells = List.of(s.cells)..[from] = -1;
    final startKing = king(v);

    void dfs(int at, bool k, List<int> taken, (int, int)? lastDir) {
      var any = false;
      for (final d in _dirs(p, k, true)) {
        final (dc, dr) = d;
        if (orthogonal && lastDir != null && dc == -lastDir.$1 && dr == -lastDir.$2) continue; // geri dönüş yok
        var c = at % n + dc, r = at ~/ n + dr;
        if (k && flyingKings) {
          while (_in(c, r) && cells[r * n + c] < 0) {
            c += dc;
            r += dr;
          }
        }
        if (!_in(c, r)) continue;
        final mid = r * n + c;
        if (owner(cells[mid]) != 1 - p || taken.contains(mid)) continue;
        if (!k && !menCaptureKings && king(cells[mid])) continue;
        var lc = c + dc, lr = r + dr;
        final lands = <int>[];
        while (_in(lc, lr) && cells[lr * n + lc] < 0) {
          lands.add(lr * n + lc);
          if (!(k && flyingKings)) break;
          lc += dc;
          lr += dr;
        }
        for (final land in lands) {
          any = true;
          final t = [...taken, mid];
          final saved = cells[mid];
          if (orthogonal) cells[mid] = -1; // Türk damasında alınan taş hemen kalkar
          var nk = k;
          final reached = land ~/ n == promoRow(p);
          if (!k && reached && stopOnPromote) {
            out.add((land, t, false));
          } else {
            if (!k && reached && promoteMidCapture) nk = true;
            dfs(land, nk, t, d);
          }
          cells[mid] = saved;
        }
      }
      if (!any && taken.isNotEmpty) out.add((at, taken, k && !startKing));
    }

    dfs(from, king(v), const [], null);
    return out;
  }

  /// Bütün yasal hamleler (hamle kodu + alım listesi).
  List<(int, List<int>, bool)> _all(GridState s) {
    final p = s.turn;
    final caps = <(int, int, List<int>, bool)>[];
    for (var i = 0; i < s.cells.length; i++) {
      if (owner(s.cells[i]) != p) continue;
      for (final (end, taken, crowned) in _captures(s, i)) {
        caps.add((i, end, taken, crowned));
      }
    }
    if (caps.isNotEmpty) {
      var list = caps;
      if (maxCapture) {
        final best = caps.map((x) => x.$3.length).reduce((a, b) => a > b ? a : b);
        list = caps.where((x) => x.$3.length == best).toList();
      }
      if (kingFirst && list.any((x) => king(s.cells[x.$1]))) {
        list = list.where((x) => king(s.cells[x.$1])).toList();
      }
      if (maxKingsTaken) {
        int kings((int, int, List<int>, bool) x) => x.$3.where((i) => king(s.cells[i])).length;
        final best = list.map(kings).reduce((a, b) => a > b ? a : b);
        list = list.where((x) => kings(x) == best).toList();
      }
      final seen = <int, int>{};
      return [
        for (final (f, e, t, c) in list) (mv(f, e, seen.update(f * 1024 + e, (x) => x + 1, ifAbsent: () => 0)), t, c),
      ];
    }
    final out = <(int, List<int>, bool)>[];
    for (var i = 0; i < s.cells.length; i++) {
      final v = s.cells[i];
      if (owner(v) != p) continue;
      final k = king(v);
      for (final (dc, dr) in _dirs(p, k, false)) {
        var c = i % n + dc, r = i ~/ n + dr;
        while (_in(c, r) && s.cells[r * n + c] < 0) {
          out.add((mv(i, r * n + c), const [], false));
          if (!(k && flyingKings)) break;
          c += dc;
          r += dr;
        }
      }
    }
    return out;
  }

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : [for (final x in _all(s)) x.$1];

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final from = mvFrom(m), to = mvTo(m);
    var taken = const <int>[];
    var crowned = false;
    for (final (code, t, c) in _all(s)) {
      if (code == m) {
        taken = t;
        crowned = c;
        break;
      }
    }
    var v = s.cells[from];
    s.cells[from] = -1;
    for (final t in taken) {
      s.cells[t] = -1;
    }
    if (!king(v) && (crowned || to ~/ n == promoRow(p))) v = p + 2;
    s.cells[to] = v;
    s.last = to;
    s.ply++;
    s.vars[1] = taken.isEmpty ? s.vars[1] + 1 : 0;
    s.turn = 1 - p;
    if (s.vars[1] >= 80 || _all(s).isEmpty) s.vars[0] = 1;
  }

  @override
  bool isOver(GridState s) => s.vars[0] == 1;

  @override
  int winner(GridState s) {
    if (!isOver(s) || s.vars[1] >= 80) return -1;
    // Sırası gelen oynayamıyor: kaybetti.
    return 1 - s.turn;
  }

  @override
  int moveOrder(GridState s, int m) {
    final f = mvFrom(m), t = mvTo(m);
    final adv = (t ~/ n - f ~/ n) * fwd(s.turn);
    return (t ~/ n == promoRow(s.turn) && !king(s.cells[f]) ? 50 : 0) + adv;
  }

  @override
  double evaluate(GridState s, int player) {
    var v = 0.0;
    final kingW = flyingKings ? 3.2 : 1.7;
    for (var i = 0; i < s.cells.length; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      final o = owner(x);
      final r = i ~/ n;
      final adv = o == 0 ? (n - 1 - r) : r;
      final val = king(x) ? kingW : 1 + adv * 0.04;
      v += o == player ? val : -val;
    }
    return v * 10;
  }

  int count(GridState s, int p) => s.cells.where((x) => owner(x) == p).length;

  @override
  String status(GridState s, String lang) => '● ${count(s, 0)}  ·  ○ ${count(s, 1)}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
