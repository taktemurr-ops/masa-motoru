import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

// ---------------------------------------------------------------- Paçisi

/// Paçisi (Hindistan'ın haç ve daire yarışı, Ludo'nun atası). Haç biçimli
/// tahtanın her kolu 3 sütun × 8 karedir. Dört oyuncu, karşılıklı ikişer
/// ortak: 0+2 ve 1+3. Taşlar ortadaki Charkoni'den çıkar, kendi kolunun orta
/// sütunundan aşağı iner, tahtanın dışını saat yönünün tersine dolaşır ve
/// yine kendi orta sütunundan yukarı çıkıp Charkoni'ye tam sayıyla girer
/// (kabuklarla 1 atılamadığından evin bir adım gerisindeki kareye basılmaz).
///
/// Zar yerine 6 deniz kabuğu atılır; ağzı yukarı bakanların sayısı:
/// 0 → 25, 1 → 10, 2–6 → 2–6. 6, 10 ve 25 "lütuf" atışıdır: yeni taş
/// çıkarılabilir ve yeniden atılır. Rakip taşın üstüne gelen onu Charkoni'ye
/// geri yollar ve yeniden atar. Çarpı işaretli 12 kale karesinde taş
/// alınamaz; rakibin durduğu kaleye girilemez. Bütün taşları eve giren
/// oyuncu, ortağının taşlarını oynamayı sürdürür; iki ortağın da bütün taşları
/// eve girince taraf kazanır.
///
/// cells[p*4+k]: -1 Charkoni'de (başlangıç), 0..82 yolda, 83 evde.
/// vars: [0] kazanan taraf+1, [1] atış değeri (0: atılacak), [2] ağzı yukarı
/// kabuk sayısı (çizim için), [3] oyuncu başına taş, [4] üst üste ek atış.
class PachisiRules extends BoardRules<GridState> {
  /// Oyuncu başına taş sayısı (gelenekte 4).
  final int pieces;
  const PachisiRules([this.pieces = 4]);

  static const home = 83;
  static const loopLen = 68;

  @override
  String get id => 'pacisi';

  @override
  int get players => 4;

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 4000;

  @override
  bool sameSide(int a, int b) => a % 2 == b % 2;

  @override
  GridState initial(SeededRandom r) {
    final cells = List<int>.filled(16, -1);
    for (var p = 0; p < 4; p++) {
      for (var k = pieces; k < 4; k++) {
        cells[p * 4 + k] = home;
      }
    }
    final s = GridState(16, 1, cells);
    s.vars[3] = pieces;
    s.turn = 0;
    return s;
  }

  /// Kabuk atışının değeri.
  static int throwValue(int mouths) => mouths == 0 ? 25 : (mouths == 1 ? 10 : mouths);
  static bool grace(int v) => v == 6 || v == 10 || v == 25;

  /// Ortak döngüdeki kare (0..67); kolun içindeki özel kareler için -1.
  static int loopSquare(int p, int prog) {
    if (prog < 7 || prog > 75) return -1;
    if (prog == 75) return (17 * p) % loopLen;
    return (17 * p + prog - 7) % loopLen;
  }

  /// Kale kareleri: her kolun ucu ve dış sütunlarda uçtan 4. kare.
  static bool castle(int sq) {
    if (sq < 0) return false;
    final m = sq % 17;
    return m == 0 || m == 4 || m == 13;
  }

  static int teamOf(int p) => p % 2;

  bool _done(GridState s, int p) {
    for (var k = 0; k < 4; k++) {
      if (s.cells[p * 4 + k] != home) return false;
    }
    return true;
  }

  /// Sırası gelen oyuncunun oynattığı taşların sahibi (kendi taşları bitince ortağı).
  int mover(GridState s) => _done(s, s.turn) ? (s.turn + 2) % 4 : s.turn;

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[1] == 0;

  @override
  void applyChance(GridState s, SeededRandom r) {
    var m = 0;
    for (var i = 0; i < 6; i++) {
      if (r.nextInt(2) == 1) m++;
    }
    s.vars[2] = m;
    s.vars[1] = throwValue(m);
  }

  /// Taşın gideceği yer (oynanamazsa null).
  int? target(GridState s, int idx, int v) {
    final p = idx ~/ 4;
    final cur = s.cells[idx];
    if (cur == home) return null;
    if (cur < 0) return grace(v) ? 0 : null;
    final t = cur + v;
    // Eve tam sayıyla girilir; 1 atılamadığı için evin bir adım gerisine basılmaz.
    if (t > home || t == home - 1) return null;
    final sq = loopSquare(p, t);
    if (castle(sq)) {
      for (var o = 0; o < 16; o++) {
        if (teamOf(o ~/ 4) == teamOf(p)) continue;
        final ov = s.cells[o];
        if (ov >= 0 && ov < home && loopSquare(o ~/ 4, ov) == sq) return null;
      }
    }
    return t;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final who = mover(s);
    final v = s.vars[1];
    final out = <int>[];
    final seen = <int>{};
    for (var k = 0; k < 4; k++) {
      final idx = who * 4 + k;
      // Aynı yerdeki taşlardan biri yeter (başlangıçtakiler dahil).
      if (!seen.add(s.cells[idx])) continue;
      if (target(s, idx, v) != null) out.add(mv(-1, idx));
    }
    return out.isEmpty ? const [kPass] : out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final v = s.vars[1];
    s.ply++;
    var again = grace(v);
    if (m != kPass) {
      final idx = mvTo(m);
      final owner = idx ~/ 4;
      final t = target(s, idx, v)!;
      s.cells[idx] = t;
      s.last = idx;
      final sq = loopSquare(owner, t);
      if (sq >= 0 && !castle(sq)) {
        for (var o = 0; o < 16; o++) {
          if (teamOf(o ~/ 4) == teamOf(owner)) continue;
          final ov = s.cells[o];
          if (ov >= 0 && ov < home && loopSquare(o ~/ 4, ov) == sq) {
            s.cells[o] = -1;
            again = true;
          }
        }
      }
      for (var team = 0; team < 2; team++) {
        if (_done(s, team) && _done(s, team + 2)) {
          s.vars[0] = team + 1;
          s.vars[1] = 0;
          return;
        }
      }
    }
    s.vars[1] = 0;
    // Ek atışlar sınırsız sürmesin diye en çok 6 üst üste.
    if (again && s.vars[4] < 6) {
      s.vars[4]++;
      return;
    }
    s.vars[4] = 0;
    s.turn = (p + 1) % 4;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  /// Kazanan taraf (0: 0+2, 1: 1+3); bitmediyse -1.
  @override
  int winner(GridState s) => s.vars[0] - 1;

  double _progress(GridState s, int p) {
    var v = 0.0;
    for (var k = 0; k < s.vars[3]; k++) {
      final x = s.cells[p * 4 + k];
      v += x < 0 ? -12 : x + (x == home ? 15 : 0);
    }
    return v;
  }

  double _team(GridState s, int t) => _progress(s, t) + _progress(s, t + 2);

  @override
  double evaluate(GridState s, int player) {
    final t = teamOf(player);
    return (_team(s, t) - _team(s, 1 - t)) / (s.vars[3] * 2);
  }

  /// Bir karenin rakip taşlardan gelecek tehlikesi (olasılıkla ağırlıklı).
  double _danger(GridState s, int team, int sq) {
    if (sq < 0 || castle(sq)) return 0;
    const prob = {2: 15, 3: 20, 4: 15, 5: 6, 6: 1, 10: 6, 25: 1};
    var d = 0.0;
    for (var o = 0; o < 16; o++) {
      if (teamOf(o ~/ 4) == team) continue;
      final ov = s.cells[o];
      if (ov < 0 || ov >= home) continue;
      prob.forEach((step, w) {
        final t = ov + step;
        if (t <= home && loopSquare(o ~/ 4, t) == sq) d += w / 64;
      });
    }
    return d;
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.length == 1) return ms.first;
    if (r.nextDouble() < noise * 0.6) return ms[r.nextInt(ms.length)];
    final team = teamOf(s.turn);
    var best = ms.first;
    var bestV = -1e9;
    for (final m in ms) {
      final c = s.copy();
      final idx = mvTo(m);
      final from = s.cells[idx];
      apply(c, m);
      final to = c.cells[idx];
      var v = (_team(c, team) - _team(c, 1 - team)) * 1.0;
      if (c.vars[0] == team + 1) v += 1e5;
      final sq = loopSquare(idx ~/ 4, to);
      if (castle(sq)) v += 4;
      v -= _danger(c, team, sq) * (to + 12) * 1.5;
      // Bulunduğu tehlikeden kurtulmak da değerli.
      v += _danger(s, team, loopSquare(idx ~/ 4, from)) * (from + 12) * 0.8;
      v += r.nextDouble() * 0.5;
      if (v > bestV) {
        bestV = v;
        best = m;
      }
    }
    return best;
  }

  @override
  String status(GridState s, String lang) {
    final v = s.vars[1];
    return v == 0 ? '' : '$v${grace(v) ? ' +' : ''}';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
