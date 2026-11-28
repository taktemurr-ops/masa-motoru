import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Tavla (ve çeşitleri). cells: 0..23 noktalar (pozitif: oyuncu 0'ın pulu,
/// negatif: oyuncu 1), 24 oyuncu 0 kırık, 25 oyuncu 1 kırık, 26/27 toplanan.
/// Oyuncu 0 23 → 0 yönünde, oyuncu 1 0 → 23 yönünde ilerler.
/// vars: [0] bitti, [1..4] kalan zarlar (0 kullanıldı), [5] zar atıldı mı,
/// [6] kazanç tipi (1 tek, 2 mars, 3 katmerli mars), [7] sıkıştırılan (Plakoto)
/// noktaların bit kümesi değil; Plakoto için ayrıca pins listesi tutulur.
/// hyper: 3 pulla tavla; nack: farklı dizilişle tavla; race: temassız
/// toplama yarışı. Bu üçü tavla kurallarıyla oynanır.
/// narde: uzun tavla; fevga gibi aynı yönde ve vurmasız, ama her turda
/// başlangıç noktasından yalnızca bir pul çıkabilir.
enum TavlaVariant { tavla, plakoto, fevga, hyper, nack, race, narde }

class TavlaState extends GridState {
  /// Plakoto: noktada altta sıkışmış rakip pulun sahibi (+1: oyuncu 0, -1: oyuncu 1, 0 yok).
  final List<int> pins;
  TavlaState(List<int> cells, List<int> vars, this.pins) : super(28, 1, cells, vars);

  @override
  TavlaState copy() => copyBase(TavlaState(List.of(cells), List.of(vars), List.of(pins)));

  @override
  Map<String, Object?> toJson() => {...super.toJson(), 'pn': pins};
}

class TavlaRules extends BoardRules<TavlaState> {
  final TavlaVariant variant;
  const TavlaRules([this.variant = TavlaVariant.tavla]);

  @override
  String get id => 'tavla-${variant.name}';

  @override
  bool get stochastic => true;

  @override
  int get maxPly => 600;

  static const bar0 = 24, bar1 = 25, off0 = 26, off1 = 27;

  /// Tavla kurallarıyla (vurma, kırık) oynanan çeşit mi.
  bool get hits => variant == TavlaVariant.tavla || variant == TavlaVariant.hyper || variant == TavlaVariant.nack || variant == TavlaVariant.race;

  /// Fevga ve Narde: iki taraf aynı yönde gider.
  bool get sameWay => variant == TavlaVariant.fevga || variant == TavlaVariant.narde;

  /// Narde: başlangıç noktası.
  int head(int p) => p == 0 ? 23 : 11;

  /// Narde: bu turda baştan çıkabilecek pul sayısı. İlk turda 6-6, 4-4 ya
  /// da 3-3 gelirse iki pul çıkabilir. pins[24]: bu turda baştan çıkan,
  /// pins[25]: turun çift zarı, pins[26]: tur başında baştaki pul sayısı.
  int headLimit(TavlaState s) => s.pins[26] == 15 && (s.pins[25] == 6 || s.pins[25] == 4 || s.pins[25] == 3) ? 2 : 1;

  /// Oyuncu başına pul sayısı.
  int get checkers => variant == TavlaVariant.hyper ? 3 : 15;

  @override
  TavlaState initial(SeededRandom r) {
    final c = List.filled(28, 0);
    switch (variant) {
      case TavlaVariant.tavla:
        c[23] = 2;
        c[12] = 5;
        c[7] = 3;
        c[5] = 5;
        c[0] = -2;
        c[11] = -5;
        c[16] = -3;
        c[18] = -5;
      case TavlaVariant.plakoto:
        c[23] = 15;
        c[0] = -15;
      case TavlaVariant.fevga:
      case TavlaVariant.narde:
        // Fevga/Narde: iki taraf da aynı yönde, karşı köşelerden başlar.
        c[23] = 15;
        c[11] = -15;
      case TavlaVariant.hyper:
        for (var i = 0; i < 3; i++) {
          c[23 - i] = 1;
          c[i] = -1;
        }
      case TavlaVariant.nack:
        c[23] = 2;
        c[22] = 2;
        c[12] = 4;
        c[7] = 3;
        c[5] = 4;
        c[0] = -2;
        c[1] = -2;
        c[11] = -4;
        c[16] = -3;
        c[18] = -4;
      case TavlaVariant.race:
        const pts = [11, 9, 7, 5, 3, 1], n = [3, 3, 3, 2, 2, 2];
        for (var i = 0; i < 6; i++) {
          c[pts[i]] = n[i];
          c[23 - pts[i]] = -n[i];
        }
    }
    final s = TavlaState(c, List.filled(8, 0), List.filled(27, 0));
    // İlk atış: zarlar eşit gelmezse büyük atan başlar (zarlarını kullanır).
    var a = 0, b = 0;
    while (a == b) {
      a = 1 + r.nextInt(6);
      b = 1 + r.nextInt(6);
    }
    s.turn = a > b ? 0 : 1;
    _setDice(s, a, b);
    return s;
  }

  void _setDice(TavlaState s, int a, int b) {
    s.vars[5] = 1;
    if (variant == TavlaVariant.narde) {
      s.pins[24] = 0;
      s.pins[25] = a == b ? a : 0;
      s.pins[26] = mine(s, head(s.turn), s.turn);
    }
    if (a == b) {
      for (var i = 1; i <= 4; i++) {
        s.vars[i] = a;
      }
    } else {
      s.vars[1] = a;
      s.vars[2] = b;
      s.vars[3] = 0;
      s.vars[4] = 0;
    }
  }

  @override
  bool needsChance(TavlaState s) => !isOver(s) && s.vars[5] == 0;

  @override
  void applyChance(TavlaState s, SeededRandom r) => _setDice(s, 1 + r.nextInt(6), 1 + r.nextInt(6));

  int sign(int p) => p == 0 ? 1 : -1;
  int mine(TavlaState s, int i, int p) => i < 24 ? (s.cells[i] * sign(p)).clamp(0, 15) : 0;
  int theirs(TavlaState s, int i, int p) => i < 24 ? (-s.cells[i] * sign(p)).clamp(0, 15) : 0;

  /// Oyuncunun yolundaki sıra (0 = başlangıç, 23 = son nokta).
  int progress(int i, int p) {
    if (sameWay && p == 1) return (11 - i + 24) % 24;
    return p == 0 ? 23 - i : i;
  }

  /// Yoldaki sıradan nokta.
  int pointAt(int prog, int p) {
    if (sameWay && p == 1) return (11 - prog + 24) % 24;
    return p == 0 ? 23 - prog : prog;
  }

  bool allHome(TavlaState s, int p) {
    if (s.cells[p == 0 ? bar0 : bar1] > 0) return false;
    for (var i = 0; i < 24; i++) {
      if (mine(s, i, p) > 0 && progress(i, p) < 18) return false;
    }
    if (variant == TavlaVariant.plakoto) {
      for (var i = 0; i < 24; i++) {
        if (s.pins[i] == sign(p) && progress(i, p) < 18) return false;
      }
    }
    return true;
  }

  bool _canLand(TavlaState s, int to, int p) {
    final t = theirs(s, to, p);
    switch (variant) {
      case TavlaVariant.tavla:
      case TavlaVariant.hyper:
      case TavlaVariant.nack:
      case TavlaVariant.race:
        return t <= 1;
      case TavlaVariant.plakoto:
        return t == 0 || (t == 1 && s.pins[to] == 0);
      case TavlaVariant.fevga:
      case TavlaVariant.narde:
        return t == 0;
    }
  }

  /// Tek zar için yasal adımlar: (from, to).
  List<(int, int)> _steps(TavlaState s, int p, int die) {
    final out = <(int, int)>[];
    final bar = p == 0 ? bar0 : bar1;
    if (hits && s.cells[bar] > 0) {
      final to = pointAt(die - 1, p);
      if (_canLand(s, to, p)) out.add((bar, to));
      return out;
    }
    final home = allHome(s, p);
    for (var i = 0; i < 24; i++) {
      if (mine(s, i, p) == 0) continue;
      if (variant == TavlaVariant.narde && i == head(p) && s.pins[24] >= headLimit(s)) continue;
      final prog = progress(i, p) + die;
      if (prog <= 23) {
        final to = pointAt(prog, p);
        if (_canLand(s, to, p)) out.add((i, to));
      } else if (home) {
        // Toplama: tam zar ya da en arkadaki pul büyük zarla.
        var further = false;
        for (var j = 0; j < 24; j++) {
          if (mine(s, j, p) > 0 && progress(j, p) < progress(i, p)) further = true;
        }
        if (prog == 24 || !further) out.add((i, p == 0 ? off0 : off1));
      }
    }
    return out;
  }

  List<int> dice(TavlaState s) => _dice(s);
  List<int> _dice(TavlaState s) => [for (var i = 1; i <= 4; i++) if (s.vars[i] > 0) s.vars[i]];

  /// En uzun kullanılabilen zar dizisi.
  int _maxUse(TavlaState s, int depth) {
    if (depth == 0) return 0;
    var best = 0;
    final seen = <int>{};
    for (final d in _dice(s)) {
      if (!seen.add(d)) continue;
      for (final (f, t) in _steps(s, s.turn, d)) {
        final c = s.copy();
        _do(c, f, t, d);
        final v = 1 + _maxUse(c, depth - 1);
        if (v > best) best = v;
        if (best == depth) return best;
      }
    }
    return best;
  }

  @override
  List<int> moves(TavlaState s) {
    if (isOver(s) || needsChance(s)) return const [];
    final dice = _dice(s);
    if (dice.isEmpty) return const [kPass];
    final need = _maxUse(s, dice.length);
    if (need == 0) return const [kPass];
    final out = <int>[];
    final seen = <int>{};
    var maxDie = 0;
    for (final d in dice) {
      if (!seen.add(d)) continue;
      for (final (f, t) in _steps(s, s.turn, d)) {
        final c = s.copy();
        _do(c, f, t, d);
        if (1 + _maxUse(c, dice.length - 1) >= need) {
          out.add(mv(f, t, d));
          if (d > maxDie) maxDie = d;
        }
      }
    }
    // Yalnız bir zar oynanabiliyorsa büyük olan oynanır.
    if (need == 1 && dice.length == 2 && dice[0] != dice[1]) {
      final big = out.where((m) => mvExtra(m) == maxDie).toList();
      if (big.isNotEmpty) return big;
    }
    return out.isEmpty ? const [kPass] : out;
  }

  void _do(TavlaState s, int f, int t, int die) {
    final p = s.turn;
    final sg = sign(p);
    if (f >= 24) {
      s.cells[f]--;
    } else {
      s.cells[f] -= sg;
      if (variant == TavlaVariant.narde && f == head(p)) s.pins[24]++;
      if (variant == TavlaVariant.plakoto && s.cells[f] == 0 && s.pins[f] != 0) {
        // Sıkışan pul serbest kalır.
        s.cells[f] = s.pins[f];
        s.pins[f] = 0;
      }
    }
    if (t >= 26) {
      s.cells[t]++;
    } else {
      if (theirs(s, t, p) == 1) {
        if (hits) {
          s.cells[t] = 0;
          s.cells[p == 0 ? bar1 : bar0]++;
        } else if (variant == TavlaVariant.plakoto) {
          s.pins[t] = -sg;
          s.cells[t] = 0;
          // Anne kuralı: rakibin başlangıç noktasındaki son pulu (hiç
          // çıkmamış) sıkıştırılırsa oyun biter, sıkıştıran iki kat kazanır;
          // sıkıştıranın kendi annesi de yerindeyse kural işlemez.
          if (progress(t, 1 - p) == 0 && mine(s, pointAt(0, p), p) == 0) {
            s.vars[0] = 1;
            s.vars[6] = 2;
            s.vars[7] = p;
          }
        }
      }
      s.cells[t] += sg;
    }
    for (var i = 1; i <= 4; i++) {
      if (s.vars[i] == die) {
        s.vars[i] = 0;
        break;
      }
    }
  }

  @override
  void apply(TavlaState s, int m) {
    final p = s.turn;
    s.ply++;
    if (m == kPass) {
      for (var i = 1; i <= 4; i++) {
        s.vars[i] = 0;
      }
    } else {
      _do(s, mvFrom(m), mvTo(m), mvExtra(m));
      s.last = mvTo(m);
      if (isOver(s)) return; // Plakoto anne kuralı
      if (variant == TavlaVariant.plakoto) s.pins[24] = 0;
    }
    if (variant == TavlaVariant.plakoto && m == kPass) {
      // İki taraf da kilitlenirse (sıkışan pullar yüzünden kimse oynayamıyor)
      // oyun sonsuza dek sürmesin: 12 boş tur sonra pip sayısı az olan kazanır.
      s.pins[24]++;
      if (s.pins[24] >= 12) {
        s.vars[0] = 1;
        s.vars[6] = 1;
        s.vars[7] = pips(s, 0) <= pips(s, 1) ? 0 : 1;
        return;
      }
    }
    if (s.cells[p == 0 ? off0 : off1] >= checkers) {
      s.vars[0] = 1;
      final o = 1 - p;
      var type = 1;
      if (s.cells[o == 0 ? off0 : off1] == 0) {
        type = 2;
        var back = s.cells[o == 0 ? bar0 : bar1] > 0;
        for (var i = 0; i < 24; i++) {
          if (mine(s, i, o) > 0 && progress(i, o) < 6) back = true;
        }
        if (back && hits) type = 3;
      }
      s.vars[6] = type;
      s.vars[7] = p;
      return;
    }
    if (_dice(s).isEmpty) {
      s.turn = 1 - p;
      s.vars[5] = 0;
    } else if (m != kPass && _maxUse(s, 1) == 0) {
      // Kalan zar oynanamıyor: sıra geçer.
      for (var i = 1; i <= 4; i++) {
        s.vars[i] = 0;
      }
      s.turn = 1 - p;
      s.vars[5] = 0;
    } else if (m == kPass) {
      s.turn = 1 - p;
      s.vars[5] = 0;
    }
  }

  @override
  bool isOver(TavlaState s) => s.vars[0] == 1;

  @override
  int winner(TavlaState s) => isOver(s) ? s.vars[7] : -1;

  int pips(TavlaState s, int p) {
    var n = s.cells[p == 0 ? bar0 : bar1] * 25;
    for (var i = 0; i < 24; i++) {
      n += mine(s, i, p) * (24 - progress(i, p));
    }
    if (variant == TavlaVariant.plakoto) {
      for (var i = 0; i < 24; i++) {
        if (s.pins[i] == sign(p)) n += 24 - progress(i, p) + 10;
      }
    }
    return n;
  }

  @override
  double evaluate(TavlaState s, int player) {
    final o = 1 - player;
    var v = (pips(s, o) - pips(s, player)) * 0.6;
    for (var i = 0; i < 24; i++) {
      final a = mine(s, i, player), b = mine(s, i, o);
      if (a == 1) v -= sameWay ? 0 : 2.5 * (progress(i, player) > 12 ? 1.4 : 1);
      if (a >= 2) v += 1.5;
      if (b == 1) v += sameWay ? 0 : 2;
      if (b >= 2) v -= 1.2;
    }
    v += (s.cells[player == 0 ? off0 : off1] - s.cells[o == 0 ? off0 : off1]) * 3;
    return v;
  }

  /// Hızlı politika: her ilk adım için kalan zarları açgözlü oynayıp
  /// son konumu değerlendir.
  @override
  int? policy(TavlaState s, double noise, SeededRandom r) {
    final ms = moves(s);
    if (ms.length == 1) return ms.first;
    final p = s.turn;
    var best = ms.first;
    var bv = -1e9;
    for (final m in ms) {
      final c = s.copy();
      apply(c, m);
      var guard = 0;
      while (c.turn == p && !isOver(c) && !needsChance(c) && guard++ < 4) {
        final next = moves(c);
        if (next.isEmpty || next.first == kPass) break;
        var nb = next.first;
        var nv = -1e9;
        for (final x in next) {
          final d = c.copy();
          apply(d, x);
          final v = isOver(d) ? 1e6 : evaluate(d, p);
          if (v > nv) {
            nv = v;
            nb = x;
          }
        }
        apply(c, nb);
      }
      final v = (isOver(c) && winner(c) == p ? 1e6 : evaluate(c, p)) + r.nextDouble() * noise * 25;
      if (v > bv) {
        bv = v;
        best = m;
      }
    }
    return best;
  }

  @override
  String status(TavlaState s, String lang) {
    return '● ${pips(s, 0)}  ·  ○ ${pips(s, 1)}';
  }

  @override
  TavlaState fromJson(Map<String, dynamic> j) {
    final s = TavlaState(intList(j['g']), intList(j['v']), intList(j['pn']));
    s.readBase(j);
    return s;
  }
}
