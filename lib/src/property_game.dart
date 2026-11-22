import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Emlak kareleri. Tür: 0 başlangıç, 1 arsa, 2 şans, 3 vergi, 4 istasyon,
/// 5 dinlenme köşesi.
class PropSquare {
  final int kind, price, group;
  const PropSquare(this.kind, [this.price = 0, this.group = -1]);
}

const kPropBoard = <PropSquare>[
  PropSquare(0),
  PropSquare(1, 60, 0),
  PropSquare(2),
  PropSquare(1, 70, 0),
  PropSquare(3, 50),
  PropSquare(1, 100, 1),
  PropSquare(5),
  PropSquare(1, 110, 1),
  PropSquare(4, 150, 6),
  PropSquare(1, 140, 2),
  PropSquare(2),
  PropSquare(1, 150, 2),
  PropSquare(5),
  PropSquare(1, 180, 3),
  PropSquare(1, 200, 3),
  PropSquare(4, 150, 6),
  PropSquare(3, 75),
  PropSquare(1, 220, 4),
  PropSquare(5),
  PropSquare(1, 240, 4),
  PropSquare(2),
  PropSquare(1, 260, 5),
  PropSquare(1, 280, 5),
  PropSquare(3, 100),
];

/// Emlak ticareti: 2-4 oyuncu, 24 karelik halka. Zar at, ilerle; sahipsiz
/// arsayı satın alabilirsin, başkasının arsasına gelirsen kira ödersin. Bir
/// renk grubunun ikisi de senindeyse kira iki katına çıkar ve evler (en çok 3)
/// kurabilirsin. Parası yetmeyen önce evlerini, sonra arsalarını bankaya yarı
/// fiyatına satar; yine ödeyemezse iflas eder ve oyun biter. O anda ya da
/// süre dolduğunda en zengin olan kazanır.
///
/// Hücreler: 24 kare; -1 banka, aksi halde sahip * 4 + ev sayısı.
/// vars: [0] sonuç (0 sürüyor, kazanan + 1), [1] aşama (0 zar, 1 satın alma,
/// 2 kurma/bitirme), [2..3] zarlar, [4..7] konumlar, [8..11] para,
/// [12] oyundakiler (bit), [13] son şans kartı + 1, [14] oyuncu sayısı.
class PropertyRules extends BoardRules<GridState> {
  final int n;
  const PropertyRules([this.n = 2]);

  @override
  String get id => 'emlak-$n';
  @override
  int get players => n;
  @override
  bool get stochastic => true;
  @override
  int get maxPly => 90 * n;

  static const startMoney = 1000, passBonus = 100;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(24, 1, List.filled(24, -1), List.filled(16, 0));
    for (var p = 0; p < n; p++) {
      s.vars[8 + p] = startMoney;
    }
    s.vars[12] = (1 << n) - 1;
    s.vars[14] = n;
    return s;
  }

  int owner(GridState s, int i) => s.cells[i] < 0 ? -1 : s.cells[i] ~/ 4;
  int houses(GridState s, int i) => s.cells[i] < 0 ? 0 : s.cells[i] % 4;
  bool alive(GridState s, int p) => (s.vars[12] >> p) & 1 == 1;
  int money(GridState s, int p) => s.vars[8 + p];
  int pos(GridState s, int p) => s.vars[4 + p];

  bool fullGroup(GridState s, int i) {
    final g = kPropBoard[i].group;
    if (g < 0 || g == 6) return false;
    final o = owner(s, i);
    for (var k = 0; k < 24; k++) {
      if (kPropBoard[k].group == g && owner(s, k) != o) return false;
    }
    return true;
  }

  int rent(GridState s, int i) {
    final sq = kPropBoard[i];
    if (sq.kind == 4) {
      final o = owner(s, i);
      final both = owner(s, 8) == o && owner(s, 15) == o;
      return both ? 80 : 30;
    }
    final base = sq.price ~/ 10;
    final h = houses(s, i);
    if (h > 0) return base * const [1, 5, 12, 25][h];
    return fullGroup(s, i) ? base * 2 : base;
  }

  int houseCost(int i) => kPropBoard[i].price ~/ 2;

  int worth(GridState s, int p) {
    if (!alive(s, p)) return 0;
    var w = money(s, p);
    for (var i = 0; i < 24; i++) {
      if (owner(s, i) == p) w += kPropBoard[i].price + houses(s, i) * houseCost(i);
    }
    return w;
  }

  @override
  bool needsChance(GridState s) => !isOver(s) && s.vars[1] == 0;

  @override
  void applyChance(GridState s, SeededRandom r) {
    final p = s.turn;
    final a = 1 + r.nextInt(6), b = 1 + r.nextInt(6);
    s.vars[2] = a;
    s.vars[3] = b;
    s.vars[13] = 0;
    _moveBy(s, p, a + b);
    _land(s, p, r, 0);
  }

  void _moveBy(GridState s, int p, int k) {
    final to = (pos(s, p) + k) % 24;
    if (k > 0 && to < pos(s, p)) s.vars[8 + p] += passBonus;
    s.vars[4 + p] = to;
    s.last = to;
  }

  void _land(GridState s, int p, SeededRandom r, int depth) {
    final i = pos(s, p);
    final sq = kPropBoard[i];
    s.vars[1] = 2;
    switch (sq.kind) {
      case 1 || 4:
        final o = owner(s, i);
        if (o < 0) {
          if (money(s, p) >= sq.price) s.vars[1] = 1;
        } else if (o != p) {
          _pay(s, p, o, rent(s, i));
        }
      case 3:
        _pay(s, p, -1, sq.price);
      case 2:
        final c = r.nextInt(6);
        s.vars[13] = c + 1;
        switch (c) {
          case 0:
            s.vars[8 + p] += 100;
          case 1:
            _pay(s, p, -1, 60);
          case 2:
            _moveBy(s, p, 24 - pos(s, p)); // başlangıca git (bonusla)
          case 3:
            s.vars[4 + p] = (pos(s, p) + 21) % 24; // üç geri
            s.last = pos(s, p);
            if (depth == 0) _land(s, p, r, 1);
          case 4:
            for (var o = 0; o < n; o++) {
              if (o != p && alive(s, o)) _pay(s, o, p, 30);
            }
          default:
            for (var o = 0; o < n; o++) {
              if (o != p && alive(s, o)) _pay(s, p, o, 20);
            }
        }
      default:
    }
    _checkEnd(s);
  }

  /// [p], [to] oyuncusuna (-1 banka) [amount] öder; gerekirse satar ya da batar.
  void _pay(GridState s, int p, int to, int amount) {
    if (!alive(s, p)) return;
    _raise(s, p, amount);
    final paid = money(s, p) >= amount ? amount : money(s, p);
    s.vars[8 + p] -= paid;
    if (to >= 0) s.vars[8 + to] += paid;
    if (paid < amount) _bankrupt(s, p);
  }

  /// Borcu ödeyecek kadar para toplayana dek önce evleri, sonra arsaları sat.
  void _raise(GridState s, int p, int need) {
    for (var pass = 0; pass < 2 && money(s, p) < need; pass++) {
      for (var i = 23; i >= 0 && money(s, p) < need; i--) {
        if (owner(s, i) != p) continue;
        if (pass == 0) {
          while (houses(s, i) > 0 && money(s, p) < need) {
            s.cells[i]--;
            s.vars[8 + p] += houseCost(i) ~/ 2;
          }
        } else {
          s.vars[8 + p] += kPropBoard[i].price ~/ 2;
          s.cells[i] = -1;
        }
      }
    }
  }

  void _bankrupt(GridState s, int p) {
    s.vars[12] &= ~(1 << p);
    s.vars[8 + p] = 0;
    for (var i = 0; i < 24; i++) {
      if (owner(s, i) == p) s.cells[i] = -1;
    }
  }

  /// İlk iflasta oyun biter; kalanlardan en zengini kazanır.
  void _checkEnd(GridState s) {
    if (s.vars[0] != 0) return;
    final left = [for (var p = 0; p < n; p++) if (alive(s, p)) p];
    if (left.length == n) return;
    var best = left.first;
    for (final p in left) {
      if (worth(s, p) > worth(s, best)) best = p;
    }
    s.vars[0] = best + 1;
  }

  int _next(GridState s, int p) {
    var q = p;
    for (var k = 0; k < n; k++) {
      q = (q + 1) % n;
      if (alive(s, q)) return q;
    }
    return p;
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s) || s.vars[1] == 0) return const [];
    final p = s.turn;
    if (!alive(s, p)) return const [kPass];
    if (s.vars[1] == 1) return [mv(-1, pos(s, p)), kPass];
    final out = <int>[];
    for (var i = 0; i < 24; i++) {
      if (owner(s, i) == p && kPropBoard[i].kind == 1 && fullGroup(s, i) && houses(s, i) < 3 && money(s, p) >= houseCost(i)) {
        out.add(mv(-1, i, 1));
      }
    }
    out.add(kPass);
    return out;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    if (m == kPass) {
      if (s.vars[1] == 1) {
        s.vars[1] = 2;
      } else {
        s.turn = _next(s, p);
        s.vars[1] = 0;
      }
    } else if (s.vars[1] == 1) {
      final i = mvTo(m);
      s.vars[8 + p] -= kPropBoard[i].price;
      s.cells[i] = p * 4;
      s.vars[1] = 2;
      s.last = i;
    } else {
      final i = mvTo(m);
      s.vars[8 + p] -= houseCost(i);
      s.cells[i]++;
      s.last = i;
    }
    s.ply++;
    _checkEnd(s);
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) {
    if (s.vars[0] != 0) return s.vars[0] - 1;
    if (s.ply < maxPly) return -1;
    var best = -1, bw = -1;
    for (var p = 0; p < n; p++) {
      final w = worth(s, p);
      if (w > bw) {
        bw = w;
        best = p;
      }
    }
    return best;
  }

  @override
  double evaluate(GridState s, int player) {
    var other = 0;
    for (var p = 0; p < n; p++) {
      if (p != player && worth(s, p) > other) other = worth(s, p);
    }
    return (worth(s, player) - other) / 30.0;
  }

  @override
  int? policy(GridState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.length == 1) return ms.first;
    final p = s.turn;
    final reserve = 60 + ((1 - noise) * 140).round();
    if (s.vars[1] == 1) {
      final price = kPropBoard[pos(s, p)].price;
      if (money(s, p) - price >= reserve || r.chance(noise * 0.3)) return ms.first;
      return kPass;
    }
    int? best;
    var bc = 1 << 20;
    for (final m in ms) {
      if (m == kPass) continue;
      final c = houseCost(mvTo(m));
      if (money(s, p) - c >= reserve + 40 && c < bc) {
        bc = c;
        best = m;
      }
    }
    return best ?? kPass;
  }

  @override
  String status(GridState s, String lang) => [for (var p = 0; p < n; p++) alive(s, p) ? '${money(s, p)}' : '—'].join('  ·  ');

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
