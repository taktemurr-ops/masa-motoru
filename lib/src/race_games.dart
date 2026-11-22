import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

// ---------------------------------------------------------------- Kızma Birader

/// Kızma Birader: 40 karelik yol, her oyuncunun 4 piyonu. 6 atan piyon
/// çıkarır ve yeniden atar. Rakibin üstüne gelen onu evine yollar.
/// cells[p*4+k]: -1 evde, 0..39 yolda (oyuncuya göre), 40..43 hedefte.
/// vars: [0] kazanan+1, [1] zar (0: atılacak), [2] kalan deneme, [3] oyuncu sayısı.
class KizmaRules extends BoardRules<GridState> {
  final int count;
  const KizmaRules([this.count = 4]);

  @override
  String get id => 'kizma-birader';

  @override
  int get players => count;

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 1200;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(16, 1, List.filled(16, -1));
    s.vars[2] = 3;
    s.vars[3] = count;
    s.turn = 0;
    return s;
  }

  int square(int p, int prog) => (p * 10 + prog) % 40;

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[1] == 0;

  @override
  void applyChance(GridState s, SeededRandom r) => s.vars[1] = 1 + r.nextInt(6);

  bool _allBase(GridState s, int p) {
    for (var k = 0; k < 4; k++) {
      final v = s.cells[p * 4 + k];
      if (v >= 0 && v < 40) return false;
      if (v >= 40) {
        // Hedefte ama hâlâ ilerleyebilir mi
        final need = 43 - v;
        var blocked = true;
        for (var j = v + 1; j <= 43; j++) {
          if (!s.cells.sublist(p * 4, p * 4 + 4).contains(j)) {
            blocked = false;
            break;
          }
        }
        if (need > 0 && !blocked) return false;
      }
    }
    return true;
  }

  int? _target(GridState s, int p, int k, int die) {
    final v = s.cells[p * 4 + k];
    final own = s.cells.sublist(p * 4, p * 4 + 4);
    if (v < 0) {
      if (die != 6) return null;
      return own.contains(0) ? null : 0;
    }
    final t = v + die;
    if (t > 43) return null;
    if (own.contains(t)) return null;
    if (v >= 40 || t >= 40) {
      // Hedef sırasında üstünden atlanmaz.
      for (var j = (v >= 40 ? v + 1 : 40); j < t; j++) {
        if (own.contains(j)) return null;
      }
    }
    return t;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final p = s.turn;
    final die = s.vars[1];
    final out = <int>[];
    // Evden çıkış zorunlu: 6 atıldıysa ve başlangıç boşsa önce çıkar.
    for (var k = 0; k < 4; k++) {
      if (_target(s, p, k, die) != null) out.add(mv(-1, p * 4 + k));
    }
    if (die == 6) {
      final exits = out.where((m) => s.cells[mvTo(m)] < 0).toList();
      if (exits.isNotEmpty) return [exits.first];
    }
    return out.isEmpty ? const [kPass] : out;
  }

  int _next(GridState s, int p) => (p + 1) % count;

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final die = s.vars[1];
    s.ply++;
    if (m != kPass) {
      final idx = mvTo(m);
      final k = idx % 4;
      final t = _target(s, p, k, die)!;
      s.cells[idx] = t;
      s.last = idx;
      if (t < 40) {
        final sq = square(p, t);
        for (var o = 0; o < count; o++) {
          if (o == p) continue;
          for (var j = 0; j < 4; j++) {
            final v = s.cells[o * 4 + j];
            if (v >= 0 && v < 40 && square(o, v) == sq) s.cells[o * 4 + j] = -1;
          }
        }
      }
      if ([for (var j = 0; j < 4; j++) s.cells[p * 4 + j]].every((v) => v >= 40)) {
        s.vars[0] = p + 1;
        return;
      }
    }
    s.vars[1] = 0;
    if (m != kPass && die == 6) {
      s.vars[2] = 3;
      return; // tekrar atar
    }
    if (m == kPass && _allBase(s, p) && s.vars[2] > 1) {
      s.vars[2]--;
      return; // üç deneme hakkı
    }
    s.turn = _next(s, p);
    s.vars[2] = 3;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  double _progress(GridState s, int p) {
    var v = 0.0;
    for (var k = 0; k < 4; k++) {
      final x = s.cells[p * 4 + k];
      v += x < 0 ? -6 : x + (x >= 40 ? 12 : 0);
    }
    return v;
  }

  @override
  double evaluate(GridState s, int player) {
    var others = 0.0;
    for (var o = 0; o < count; o++) {
      if (o != player) others += _progress(s, o);
    }
    return _progress(s, player) - others / (count - 1);
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.length == 1) return ms.first;
    if (r.nextDouble() < noise * 0.6) return ms[r.nextInt(ms.length)];
    final p = s.turn;
    var best = ms.first;
    var bestV = -1e9;
    for (final m in ms) {
      final c = s.copy();
      apply(c, m);
      var v = evaluate(c, p) * 2;
      // Tehlike: hedef karenin arkasındaki 6 karede rakip piyon var mı
      final k = mvTo(m) % 4;
      final t = c.cells[p * 4 + k];
      if (t >= 0 && t < 40) {
        final sq = square(p, t);
        for (var o = 0; o < count; o++) {
          if (o == p) continue;
          for (var j = 0; j < 4; j++) {
            final ov = c.cells[o * 4 + j];
            if (ov < 0 || ov >= 40) continue;
            final dist = (sq - square(o, ov) + 40) % 40;
            if (dist >= 1 && dist <= 6) v -= 8;
          }
        }
      }
      v += r.nextDouble();
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    return best;
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ---------------------------------------------------------------- Yılan merdiven

/// Yılan merdiven, stüdyo yorumu: her turda iki zar atılır, hangisiyle
/// ilerleyeceğini sen seçersin. Tahta (yılanlar ve merdivenler) bölüme göre
/// üretilir. cells[0..3]: oyuncu konumları (0 başlangıç, 100 bitiş),
/// cells[4+i]: i karesinden gidilen kare (yoksa -1).
/// vars: [0] kazanan+1, [1..2] zarlar (0: atılacak).
class SnakesRules extends BoardRules<GridState> {
  final int count;
  const SnakesRules([this.count = 2]);

  @override
  String get id => 'yilan-merdiven';

  @override
  int get players => count;

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 800;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(4 + 101, 1, [0, 0, 0, 0, ...List.filled(101, -1)]);
    final used = <int>{0, 1, 100};
    int pick(int lo, int hi) {
      for (;;) {
        final x = lo + r.nextInt(hi - lo + 1);
        if (used.add(x)) return x;
      }
    }

    final ladders = 7 + r.nextInt(3), snakes = 7 + r.nextInt(3);
    for (var i = 0; i < ladders; i++) {
      final a = pick(2, 80);
      final b = (a + 10 + r.nextInt(30)).clamp(a + 8, 99);
      if (!used.add(b)) continue;
      s.cells[4 + a] = b;
    }
    for (var i = 0; i < snakes; i++) {
      final a = pick(20, 99);
      final b = (a - 10 - r.nextInt(35)).clamp(2, a - 8);
      if (!used.add(b)) continue;
      s.cells[4 + a] = b;
    }
    return s;
  }

  int jump(GridState s, int sq) => sq <= 100 && s.cells[4 + sq] >= 0 ? s.cells[4 + sq] : sq;

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[1] == 0;

  @override
  void applyChance(GridState s, SeededRandom r) {
    s.vars[1] = 1 + r.nextInt(6);
    s.vars[2] = 1 + r.nextInt(6);
  }

  int landing(GridState s, int p, int die) {
    var t = s.cells[p] + die;
    if (t > 100) t = 200 - t; // geri sekme
    return jump(s, t);
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    return s.vars[1] == s.vars[2] ? [mv(-1, 0)] : [mv(-1, 0), mv(-1, 1)];
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final die = s.vars[1 + mvTo(m)];
    s.cells[p] = landing(s, p, die);
    s.last = p;
    s.ply++;
    s.vars[1] = 0;
    s.vars[2] = 0;
    if (s.cells[p] == 100) {
      s.vars[0] = p + 1;
      return;
    }
    s.turn = (p + 1) % count;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  @override
  double evaluate(GridState s, int player) {
    var others = 0.0;
    for (var o = 0; o < count; o++) {
      if (o != player) others += s.cells[o];
    }
    return s.cells[player] - others / (count - 1);
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.length == 1 || r.nextDouble() < noise * 0.7) return ms[r.nextInt(ms.length)];
    final p = s.turn;
    final a = landing(s, p, s.vars[1]), b = landing(s, p, s.vars[2]);
    return a >= b ? ms[0] : ms[1];
  }

  @override
  String status(GridState s, String lang) => [for (var p = 0; p < count; p++) '${s.cells[p]}'].join(' · ');

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
