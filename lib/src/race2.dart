import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Zarlı yarış oyunlarının ortak yardımcısı: rastgele ama güçlüye yakın
/// politika (her hamleyi dener, değerlendirir, gürültü ekler).
int pickByEval<S extends BoardState>(BoardRules<S> rules, S s, double noise, SeededRandom r, double Function(S after, int m) bonus) {
  final ms = rules.moves(s);
  if (ms.length == 1) return ms.first;
  if (r.nextDouble() < noise * 0.6) return ms[r.nextInt(ms.length)];
  final p = s.turn;
  var best = ms.first;
  var bestV = -1e9;
  for (final m in ms) {
    final c = rules.parse(s.serialize());
    rules.apply(c, m);
    final v = rules.evaluate(c, p) * 2 + bonus(c, m) + r.nextDouble() * (0.5 + noise * 6);
    if (v > bestV) {
      bestV = v;
      best = m;
    }
  }
  return best;
}

// ======================================================================
// Ur kraliyet oyunu: 7 taş, dört üçgen zar (0–4). Yol 14 kare; 5–12 ortak.
// Gül karelerine (4, 8, 14) gelen yeniden atar; ortadaki gül güvenlidir.
// cells[p*7+k]: 0 evde, 1..14 yolda, 15 bitti. vars: [0] kazanan+1,
// [1] zar (0 atılacak, 1..5: değer+1), [2] art arda pas sayacı.

class UrRules extends BoardRules<GridState> {
  const UrRules();

  @override
  String get id => 'ur';

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 900;

  static const rosettes = {4, 8, 14};

  @override
  GridState initial(SeededRandom r) => GridState(14, 1, List.filled(14, 0));

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[1] == 0;

  @override
  void applyChance(GridState s, SeededRandom r) {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      v += r.nextInt(2);
    }
    s.vars[1] = v + 1;
  }

  int roll(GridState s) => s.vars[1] - 1;
  bool shared(int pos) => pos >= 5 && pos <= 12;

  int? target(GridState s, int p, int k) {
    final v = s.cells[p * 7 + k];
    final d = roll(s);
    if (d == 0 || v >= 15) return null;
    final t = v + d;
    if (t > 15) return null;
    if (t == 15) return 15;
    for (var j = 0; j < 7; j++) {
      if (s.cells[p * 7 + j] == t) return null;
    }
    if (shared(t) && rosettes.contains(t)) {
      for (var j = 0; j < 7; j++) {
        if (s.cells[(1 - p) * 7 + j] == t) return null; // güvenli gül
      }
    }
    return t;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    var homeDone = false;
    for (var k = 0; k < 7; k++) {
      if (target(s, p, k) == null) continue;
      if (s.cells[p * 7 + k] == 0) {
        if (homeDone) continue; // evdeki taşlar aynı hamle
        homeDone = true;
      }
      out.add(mv(-1, p * 7 + k));
    }
    return out.isEmpty ? const [kPass] : out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    var again = false;
    if (m != kPass) {
      final idx = mvTo(m);
      final t = target(s, p, idx % 7)!;
      s.cells[idx] = t;
      s.last = idx;
      if (shared(t)) {
        for (var j = 0; j < 7; j++) {
          if (s.cells[(1 - p) * 7 + j] == t) s.cells[(1 - p) * 7 + j] = 0;
        }
      }
      if ([for (var j = 0; j < 7; j++) s.cells[p * 7 + j]].every((v) => v == 15)) {
        s.vars[0] = p + 1;
        return;
      }
      again = rosettes.contains(t);
    }
    s.vars[1] = 0;
    if (!again) s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  double _prog(GridState s, int p) {
    var v = 0.0;
    for (var k = 0; k < 7; k++) {
      final x = s.cells[p * 7 + k];
      v += x == 15 ? 20 : x.toDouble();
      if (x == 8) v += 2;
    }
    return v;
  }

  @override
  double evaluate(GridState s, int player) => _prog(s, player) - _prog(s, 1 - player);

  @override
  int? policy(GridState s, double noise, SeededRandom r) => pickByEval(this, s, noise, r, (c, m) {
        if (m == kPass) return 0;
        final t = c.cells[mvTo(m)];
        return (rosettes.contains(t) ? 4 : 0) + (t == 15 ? 3 : 0);
      });

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Senet: 30 kare (üç sıra, yılan gibi). Dört çubuk: beyaz yüz sayısı
// 1–4, hiçbiri 0 ise 5. 1, 4 ve 5 yeniden attırır. Rakibin tek taşıyla
// yer değiştirilir; yan yana iki taş korunur, üç taş geçit vermez.
// 26. kareye tam gelinmeden geçilmez; 27 suyu taşı 15'e geri yollar.
// cells[p*5+k]: 1..30 kare, 31 bitti. vars: [0] kazanan+1, [1] atış+1.

class SenetRules extends BoardRules<GridState> {
  const SenetRules();

  @override
  String get id => 'senet';

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 900;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(10, 1, List.filled(10, 0));
    for (var k = 0; k < 5; k++) {
      s.cells[k] = 1 + 2 * k; // oyuncu 0: 1,3,5,7,9
      s.cells[5 + k] = 2 + 2 * k; // oyuncu 1: 2,4,6,8,10
    }
    s.turn = 0;
    return s;
  }

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[1] == 0;

  @override
  void applyChance(GridState s, SeededRandom r) {
    var v = 0;
    for (var i = 0; i < 4; i++) {
      v += r.nextInt(2);
    }
    s.vars[1] = (v == 0 ? 5 : v) + 1;
  }

  int roll(GridState s) => s.vars[1] - 1;

  int owner(GridState s, int sq) {
    for (var i = 0; i < 10; i++) {
      if (s.cells[i] == sq) return i ~/ 5;
    }
    return -1;
  }

  int? target(GridState s, int p, int k) {
    final v = s.cells[p * 5 + k];
    if (v >= 31) return null;
    final d = roll(s);
    // Son kareler: 26'dan 5 ile çıkış; 28/29/30'dan tam atışla çıkış.
    if (v >= 26) {
      if (v == 26 && d == 5) return 31;
      if (v == 28 && d == 3 || v == 29 && d == 2 || v == 30 && d == 1) return 31;
      if (v == 26 && d == 1) return 27;
      if (v == 26 && d < 5) {
        final t = v + d;
        return owner(s, t) == p ? null : (owner(s, t) == 1 - p && _guarded(s, t, 1 - p) ? null : t);
      }
      return null;
    }
    final t = v + d;
    if (v < 26 && t > 26) return null; // 26'ya tam gelinmeli
    // Üç rakip taş yan yana: geçit yok.
    for (var x = v + 1; x < t; x++) {
      if (owner(s, x) == 1 - p && owner(s, x + 1) == 1 - p && owner(s, x + 2) == 1 - p) return null;
    }
    final o = owner(s, t);
    if (o == p) return null;
    if (o == 1 - p && _guarded(s, t, 1 - p)) return null;
    return t;
  }

  bool _guarded(GridState s, int sq, int o) => owner(s, sq - 1) == o || owner(s, sq + 1) == o;

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    for (var k = 0; k < 5; k++) {
      if (target(s, p, k) != null) out.add(mv(-1, p * 5 + k));
    }
    return out.isEmpty ? const [kPass] : out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final d = roll(s);
    s.ply++;
    if (m != kPass) {
      final idx = mvTo(m);
      final from = s.cells[idx];
      var t = target(s, p, idx % 5)!;
      if (t == 27) {
        // Su: 15'e (doluysa geriye doğru ilk boşa) döner.
        t = 15;
        while (owner(s, t) >= 0 && t > 1) {
          t--;
        }
      }
      for (var i = 0; i < 10; i++) {
        if (s.cells[i] == t && t <= 30) s.cells[i] = from; // yer değiştir
      }
      s.cells[idx] = t;
      s.last = idx;
      if ([for (var k = 0; k < 5; k++) s.cells[p * 5 + k]].every((v) => v == 31)) {
        s.vars[0] = p + 1;
        return;
      }
    }
    s.vars[1] = 0;
    if (!(d == 1 || d == 4 || d == 5)) s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  double _prog(GridState s, int p) {
    var v = 0.0;
    for (var k = 0; k < 5; k++) {
      final x = s.cells[p * 5 + k];
      v += x >= 31 ? 40 : x.toDouble();
    }
    return v;
  }

  @override
  double evaluate(GridState s, int player) => _prog(s, player) - _prog(s, 1 - player);

  @override
  int? policy(GridState s, double noise, SeededRandom r) => pickByEval(this, s, noise, r, (c, m) {
        if (m == kPass) return 0;
        final t = c.cells[mvTo(m)];
        return (t == 26 ? 3 : 0) + (t == 31 ? 4 : 0) + (_guarded(c, t, s.turn) ? 1.5 : 0);
      });

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Yut: dört çubuk (do 1, gae 2, geol 3, yut 4, mo 5; yut ve mo yeniden
// attırır). 29 duraklı tahta; köşeye tam gelen kısa yoldan gider.
// Kendi taşının üstüne gelen onunla yığılır; rakibe gelen onu (yığınıyla)
// eve yollar ve yeniden atar. Dört taşı da ilk bitiren kazanır.
// Duraklar: 0..19 dış halka (0 başlangıç/bitiş), 20–23 köşe 5'ten çapraz
// (a1,a2,a3,a4), 24–27 köşe 10'dan çapraz (b1,b2,b3,b4), 28 merkez.
// cells[p*4+k]: -1 evde, 0..28 durak, 29 bitti. vars: [0] kazanan+1, [1] atış+1.

class YutRules extends BoardRules<GridState> {
  const YutRules();

  @override
  String get id => 'yut';

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 900;

  static const home = -1, done = 29, center = 28;

  @override
  GridState initial(SeededRandom r) => GridState(8, 1, List.filled(8, home));

  @override
  bool needsChance(GridState s) => s.vars[0] == 0 && s.vars[1] == 0;

  @override
  void applyChance(GridState s, SeededRandom r) {
    var flat = 0;
    for (var i = 0; i < 4; i++) {
      flat += r.nextInt(2);
    }
    s.vars[1] = (flat == 0 ? 5 : flat) + 1;
  }

  int roll(GridState s) => s.vars[1] - 1;

  /// Bir adım; [first] hamlenin ilk adımı mı, [prev] önceki durak.
  static int step(int at, int prev, bool first) {
    if (at == home) return 1;
    if (first && at == 5) return 20;
    if (first && at == 10) return 24;
    if (first && at == center) return 26;
    switch (at) {
      case 20:
        return 21;
      case 21:
        return center;
      case center:
        return prev == 21 ? 22 : 26;
      case 22:
        return 23;
      case 23:
        return 15;
      case 24:
        return 25;
      case 25:
        return center;
      case 26:
        return 27;
      case 27:
        return done;
      case 19:
        return done;
      default:
        return at + 1;
    }
  }

  static int travel(int from, int n) {
    var at = from, prev = -2;
    for (var i = 0; i < n; i++) {
      final nx = step(at, prev, i == 0);
      prev = at;
      at = nx;
      if (at == done) return done;
    }
    return at;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final p = s.turn;
    final out = <int>[];
    final seen = <int>{};
    for (var k = 0; k < 4; k++) {
      final v = s.cells[p * 4 + k];
      if (v == done || !seen.add(v)) continue; // yığın ve evdekiler tek hamle
      out.add(mv(-1, p * 4 + k));
    }
    return out.isEmpty ? const [kPass] : out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    final d = roll(s);
    s.ply++;
    var again = d >= 4;
    if (m != kPass) {
      final idx = mvTo(m);
      final from = s.cells[idx];
      final t = travel(from, d);
      // Yığın: aynı duraktaki kendi taşları birlikte gider (evdekiler tek tek).
      for (var k = 0; k < 4; k++) {
        final j = p * 4 + k;
        if (j == idx || (from != home && s.cells[j] == from)) s.cells[j] = t;
      }
      s.last = idx;
      if (t != done) {
        for (var k = 0; k < 4; k++) {
          final j = (1 - p) * 4 + k;
          if (s.cells[j] == t) {
            s.cells[j] = home;
            again = true;
          }
        }
      }
      if ([for (var k = 0; k < 4; k++) s.cells[p * 4 + k]].every((v) => v == done)) {
        s.vars[0] = p + 1;
        return;
      }
    }
    s.vars[1] = 0;
    if (!again) s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  /// Bitişe kalan adım (kısa yol hesaba katılır).
  static int remaining(int v) {
    if (v == done) return 0;
    if (v == home) return 21;
    var best = 99;
    for (var n = 1; n <= 25; n++) {
      if (travel(v, n) == done) {
        best = n;
        break;
      }
    }
    return best;
  }

  @override
  double evaluate(GridState s, int player) {
    double prog(int p) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        v += 25 - remaining(s.cells[p * 4 + k]);
      }
      return v;
    }

    return prog(player) - prog(1 - player);
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) => pickByEval(this, s, noise, r, (c, m) => 0);

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

// ======================================================================
// Amiral battı: iki gizli filo. Sırayla rakip denizde bir kareye atış
// yapılır; bütün gemileri ilk batıran kazanır. Yapay zekâ yalnızca
// atışlarının sonucunu bilir (av ve hedef taktiği).
// cells: 0..n²-1 oyuncu 0'ın denizi, n²..2n²-1 oyuncu 1'in denizi.
// Değer: gemi (0..4, yok 7) + 8 × vuruldu. vars: [0] kazanan+1.

class NavalRules extends BoardRules<GridState> {
  final int n;
  const NavalRules(this.n);

  @override
  String get id => 'amiral-$n';

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 2 * n * n + 2;

  List<int> get fleet => n >= 10 ? const [5, 4, 3, 3, 2] : const [4, 3, 3, 2];

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(n, 2 * n, List.filled(2 * n * n, 7));
    for (var p = 0; p < 2; p++) {
      for (var ship = 0; ship < fleet.length; ship++) {
        final len = fleet[ship];
        while (true) {
          final horiz = r.nextInt(2) == 0;
          final c = r.nextInt(horiz ? n - len + 1 : n), row = r.nextInt(horiz ? n : n - len + 1);
          final cells = [for (var i = 0; i < len; i++) horiz ? row * n + c + i : (row + i) * n + c];
          // Gemiler birbirine değmez (çapraz dahil).
          var ok = true;
          for (final x in cells) {
            final xc = x % n, xr = x ~/ n;
            for (var dr = -1; dr <= 1 && ok; dr++) {
              for (var dc = -1; dc <= 1 && ok; dc++) {
                final yc = xc + dc, yr = xr + dr;
                if (yc < 0 || yr < 0 || yc >= n || yr >= n) continue;
                if (s.cells[p * n * n + yr * n + yc] != 7) ok = false;
              }
            }
          }
          if (!ok) continue;
          for (final x in cells) {
            s.cells[p * n * n + x] = ship;
          }
          break;
        }
      }
    }
    return s;
  }

  int sea(int p) => p * n * n;
  bool shot(int v) => v >= 8;
  int ship(int v) => v % 8;

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final base = sea(1 - s.turn);
    return [for (var i = 0; i < n * n; i++) if (!shot(s.cells[base + i])) mv(-1, base + i)];
  }

  bool sunk(GridState s, int p, int sh) {
    for (var i = 0; i < n * n; i++) {
      final v = s.cells[sea(p) + i];
      if (ship(v) == sh && !shot(v)) return false;
    }
    return true;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    s.ply++;
    final i = mvTo(m);
    s.cells[i] += 8;
    s.last = i;
    var left = false;
    for (var j = 0; j < n * n; j++) {
      final v = s.cells[sea(1 - p) + j];
      if (ship(v) != 7 && !shot(v)) left = true;
    }
    if (!left) {
      s.vars[0] = p + 1;
      return;
    }
    s.turn = 1 - p;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] - 1;

  @override
  double evaluate(GridState s, int player) {
    int hits(int p) {
      var h = 0;
      for (var j = 0; j < n * n; j++) {
        final v = s.cells[sea(p) + j];
        if (ship(v) != 7 && shot(v)) h++;
      }
      return h;
    }

    return (hits(1 - player) - hits(player)).toDouble();
  }

  /// Av ve hedef: vurulmuş ama batmamış gemi parçalarının çevresine,
  /// yoksa dama deseninde rastgele kareye atış. Gemi yerleri okunmaz;
  /// yalnızca atış sonuçları (isabet, karavana, batma) kullanılır.
  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.isEmpty) return null;
    final base = sea(1 - s.turn);
    if (r.nextDouble() < noise * 0.7) return ms[r.nextInt(ms.length)];
    // Açık isabetler: vurulmuş, gemisi henüz batmamış kareler.
    final open = <int>[];
    for (var j = 0; j < n * n; j++) {
      final v = s.cells[base + j];
      if (shot(v) && ship(v) != 7 && !sunk(s, 1 - s.turn, ship(v))) open.add(j);
    }
    bool free(int c, int row) => c >= 0 && row >= 0 && c < n && row < n && !shot(s.cells[base + row * n + c]);
    if (open.isNotEmpty) {
      final cand = <int>[];
      // Aynı sırada iki isabet varsa o doğrultuda devam et.
      for (final a in open) {
        for (final b in open) {
          if (a == b) continue;
          final dc = (b % n - a % n).sign, dr = (b ~/ n - a ~/ n).sign;
          if ((dc != 0) == (dr != 0)) continue;
          var c = b % n + dc, row = b ~/ n + dr;
          while (c >= 0 && row >= 0 && c < n && row < n && shot(s.cells[base + row * n + c]) && open.contains(row * n + c)) {
            c += dc;
            row += dr;
          }
          if (free(c, row)) cand.add(row * n + c);
        }
      }
      if (cand.isEmpty) {
        for (final a in open) {
          for (final (dc, dr) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
            if (free(a % n + dc, a ~/ n + dr)) cand.add((a ~/ n + dr) * n + a % n + dc);
          }
        }
      }
      if (cand.isNotEmpty) return mv(-1, base + cand[r.nextInt(cand.length)]);
    }
    // Av: batmış gemilerin çevresi boş bilinir; dama deseni tercih edilir.
    final hunt = <int>[];
    for (final m in ms) {
      final j = mvTo(m) - base;
      final c = j % n, row = j ~/ n;
      var nearSunk = false;
      for (var dr = -1; dr <= 1; dr++) {
        for (var dc = -1; dc <= 1; dc++) {
          final yc = c + dc, yr = row + dr;
          if (yc < 0 || yr < 0 || yc >= n || yr >= n) continue;
          final v = s.cells[base + yr * n + yc];
          if (shot(v) && ship(v) != 7 && sunk(s, 1 - s.turn, ship(v))) nearSunk = true;
        }
      }
      if (nearSunk) continue;
      if ((c + row).isEven) hunt.add(m);
    }
    if (hunt.isNotEmpty) return hunt[r.nextInt(hunt.length)];
    return ms[r.nextInt(ms.length)];
  }

  @override
  String status(GridState s, String lang) {
    int left(int p) {
      var k = 0;
      for (var sh = 0; sh < fleet.length; sh++) {
        if (!sunk(s, p, sh)) k++;
      }
      return k;
    }

    return '⚓ ${left(0)} · ${left(1)}';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
