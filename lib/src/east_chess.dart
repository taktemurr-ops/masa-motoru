import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// Kesişim tahtalı doğu satrançları (9 sütun × 10 sıra). Taş kodu: renk * 8 + tür.
const xS = 1, xC = 2, xR = 3, xH = 4, xE = 5, xA = 6, xG = 7;
int eColor(int v) => v < 0 ? -1 : v ~/ 8;
int eType(int v) => v < 0 ? 0 : v % 8;

/// Çin satrancı (janggi: false) ve Kore satrancı (janggi: true).
/// Oyuncu 0 altta, yukarı oynar. vars: [0] sonuç (0 sürüyor, 1/2 kazanan + 1,
/// 3 berabere), [1] art arda pas (yalnız Kore).
class XiangqiRules extends BoardRules<GridState> {
  final bool janggi;
  const XiangqiRules({this.janggi = false});

  static const cols = 9, rows = 10;

  @override
  String get id => janggi ? 'janggi' : 'xiangqi';

  @override
  int get maxPly => 260;

  @override
  double get decisive => 120;

  static const _orth = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  static const _diag = [(1, 1), (1, -1), (-1, 1), (-1, -1)];

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(cols, rows, List.filled(cols * rows, -1), List.filled(8, 0));
    for (final p in const [0, 1]) {
      int row(int fromBottom) => p == 0 ? rows - 1 - fromBottom : fromBottom;
      void put(int c, int fb, int t) => s.cells[row(fb) * cols + c] = p * 8 + t;
      var mid = const [xH, xE, xE, xH];
      if (janggi) {
        mid = const [
          [xH, xE, xE, xH],
          [xE, xH, xE, xH],
          [xH, xE, xH, xE],
          [xE, xH, xH, xE],
        ][r.nextInt(4)];
      }
      put(0, 0, xR);
      put(8, 0, xR);
      if (janggi) {
        put(1, 0, mid[0]);
        put(2, 0, mid[1]);
        put(6, 0, mid[2]);
        put(7, 0, mid[3]);
        put(3, 0, xA);
        put(5, 0, xA);
        put(4, 1, xG);
      } else {
        put(1, 0, xH);
        put(7, 0, xH);
        put(2, 0, xE);
        put(6, 0, xE);
        put(3, 0, xA);
        put(5, 0, xA);
        put(4, 0, xG);
      }
      put(1, 2, xC);
      put(7, 2, xC);
      for (final c in const [0, 2, 4, 6, 8]) {
        put(c, 3, xS);
      }
    }
    return s;
  }

  bool _in(int c, int r) => c >= 0 && r >= 0 && c < cols && r < rows;

  /// [p] oyuncusunun sarayı.
  bool ownPalace(int c, int r, int p) => c >= 3 && c <= 5 && (p == 0 ? r >= 7 : r <= 2);
  bool anyPalace(int c, int r) => c >= 3 && c <= 5 && (r >= 7 || r <= 2);

  /// Kore satrancında saray köşegeni: iki nokta aynı saraydaysa ve biri merkezse.
  bool diagLink(int c, int r, int dc, int dr) {
    final c2 = c + dc, r2 = r + dr;
    if (!anyPalace(c, r) || !anyPalace(c2, r2)) return false;
    if ((r >= 7) != (r2 >= 7)) return false;
    final rc = r >= 7 ? 8 : 1;
    return (c == 4 && r == rc) || (c2 == 4 && r2 == rc);
  }

  int fwd(int p) => p == 0 ? -1 : 1;

  /// [p] oyuncusunun yalancı-yasal tahta hamleleri.
  void gen(GridState s, int p, void Function(int from, int to) add) {
    final cells = s.cells;
    for (var i = 0; i < cells.length; i++) {
      final v = cells[i];
      if (eColor(v) != p) continue;
      final t = eType(v);
      final c0 = i % cols, r0 = i ~/ cols;
      bool tryTo(int c, int r) {
        if (!_in(c, r)) return false;
        final o = eColor(cells[r * cols + c]);
        if (o != p) add(i, r * cols + c);
        return o < 0;
      }

      switch (t) {
        case xG || xA:
          if (janggi) {
            for (final (dc, dr) in _orth) {
              if (ownPalace(c0 + dc, r0 + dr, p)) tryTo(c0 + dc, r0 + dr);
            }
            for (final (dc, dr) in _diag) {
              if (diagLink(c0, r0, dc, dr) && ownPalace(c0 + dc, r0 + dr, p)) tryTo(c0 + dc, r0 + dr);
            }
          } else {
            for (final (dc, dr) in t == xG ? _orth : _diag) {
              if (ownPalace(c0 + dc, r0 + dr, p)) tryTo(c0 + dc, r0 + dr);
            }
          }
        case xE:
          if (janggi) {
            for (final (dc, dr) in _orth) {
              final c1 = c0 + dc, r1 = r0 + dr;
              if (!_in(c1, r1) || cells[r1 * cols + c1] >= 0) continue;
              for (final sgn in const [-1, 1]) {
                final pc = dc != 0 ? dc : sgn, pr = dr != 0 ? dr : sgn;
                final c2 = c1 + pc, r2 = r1 + pr;
                if (!_in(c2, r2) || cells[r2 * cols + c2] >= 0) continue;
                tryTo(c2 + pc, r2 + pr);
              }
            }
          } else {
            for (final (dc, dr) in _diag) {
              final c1 = c0 + dc, r1 = r0 + dr, c2 = c0 + 2 * dc, r2 = r0 + 2 * dr;
              if (!_in(c2, r2) || cells[r1 * cols + c1] >= 0) continue;
              if (p == 0 ? r2 < 5 : r2 > 4) continue;
              tryTo(c2, r2);
            }
          }
        case xH:
          for (final (dc, dr) in _orth) {
            final c1 = c0 + dc, r1 = r0 + dr;
            if (!_in(c1, r1) || cells[r1 * cols + c1] >= 0) continue;
            for (final sgn in const [-1, 1]) {
              tryTo(dc != 0 ? c1 + dc : c1 + sgn, dr != 0 ? r1 + dr : r1 + sgn);
            }
          }
        case xR:
          for (final (dc, dr) in _orth) {
            var c = c0 + dc, r = r0 + dr;
            while (tryTo(c, r)) {
              c += dc;
              r += dr;
            }
          }
          if (janggi) {
            for (final (dc, dr) in _diag) {
              var c = c0, r = r0;
              while (diagLink(c, r, dc, dr)) {
                c += dc;
                r += dr;
                if (!tryTo(c, r)) break;
              }
            }
          }
        case xC:
          void line(int dc, int dr, bool Function(int c, int r) step) {
            var c = c0, r = r0;
            var screen = false;
            while (step(c, r)) {
              c += dc;
              r += dr;
              final v2 = cells[r * cols + c];
              if (!screen) {
                if (v2 >= 0) {
                  if (janggi && eType(v2) == xC) return;
                  screen = true;
                } else if (!janggi) {
                  add(i, r * cols + c);
                }
              } else {
                if (v2 < 0) {
                  if (janggi) add(i, r * cols + c);
                  continue;
                }
                if (eColor(v2) != p && !(janggi && eType(v2) == xC)) add(i, r * cols + c);
                return;
              }
            }
          }
          for (final (dc, dr) in _orth) {
            line(dc, dr, (c, r) => _in(c + dc, r + dr));
          }
          if (janggi) {
            for (final (dc, dr) in _diag) {
              line(dc, dr, (c, r) => diagLink(c, r, dc, dr));
            }
          }
        case xS:
          final f = fwd(p);
          tryTo(c0, r0 + f);
          final crossed = p == 0 ? r0 <= 4 : r0 >= 5;
          if (janggi || crossed) {
            tryTo(c0 - 1, r0);
            tryTo(c0 + 1, r0);
          }
          if (janggi) {
            for (final dc in const [-1, 1]) {
              if (diagLink(c0, r0, dc, f)) tryTo(c0 + dc, r0 + f);
            }
          }
      }
    }
  }

  int generalSq(GridState s, int p) => s.cells.indexOf(p * 8 + xG);

  bool attacked(GridState s, int sq, int by) {
    var hit = false;
    gen(s, by, (f, t) {
      if (t == sq) hit = true;
    });
    return hit;
  }

  bool _facing(GridState s) {
    final a = generalSq(s, 0), b = generalSq(s, 1);
    if (a < 0 || b < 0 || a % cols != b % cols) return false;
    for (var i = b + cols; i < a; i += cols) {
      if (s.cells[i] >= 0) return false;
    }
    return true;
  }

  bool inCheck(GridState s, int p) {
    final g = generalSq(s, p);
    if (g < 0) return true;
    if (!janggi && _facing(s)) return true;
    return attacked(s, g, 1 - p);
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    return _legal(s);
  }

  List<int> _legal(GridState s) {
    final p = s.turn;
    final out = <int>[];
    gen(s, p, (f, t) {
      if (_safe(s, p, f, t)) out.add(mv(f, t));
    });
    if (janggi && !inCheck(s, p)) out.add(kPass);
    return out;
  }

  bool _safe(GridState s, int p, int f, int t) {
    final a = s.cells[f], b = s.cells[t];
    s.cells[t] = a;
    s.cells[f] = -1;
    final ok = !inCheck(s, p);
    s.cells[f] = a;
    s.cells[t] = b;
    return ok;
  }

  /// Tahtada en az bir yasal hamle var mı (pas sayılmaz).
  bool hasLegal(GridState s, int p) {
    final cand = <int>[];
    gen(s, p, (f, t) => cand.add(mv(f, t)));
    for (final m in cand) {
      if (_safe(s, p, mvFrom(m), mvTo(m))) return true;
    }
    return false;
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    if (m == kPass) {
      s.vars[1]++;
    } else {
      final f = mvFrom(m), t = mvTo(m);
      s.cells[t] = s.cells[f];
      s.cells[f] = -1;
      s.vars[1] = 0;
      s.last = t;
    }
    s.ply++;
    s.turn = 1 - p;
    final o = 1 - p;
    if (janggi && s.vars[1] >= 2) {
      s.vars[0] = points(s, 0) * 2 > points(s, 1) * 2 + 3 ? 1 : 2;
      return;
    }
    if (!hasLegal(s, o) && (!janggi || inCheck(s, o))) {
      s.vars[0] = p + 1;
      return;
    }
    if (s.ply >= maxPly) {
      if (janggi) {
        s.vars[0] = points(s, 0) * 2 > points(s, 1) * 2 + 3 ? 1 : 2;
      } else {
        s.vars[0] = 3;
      }
    }
  }

  /// Kore satrancı puanı (oyuncu 1 ayrıca 1,5 puan alır).
  static const _pts = [0, 2, 7, 13, 5, 3, 3, 0];
  int points(GridState s, int p) {
    var t = 0;
    for (final v in s.cells) {
      if (eColor(v) == p) t += _pts[eType(v)];
    }
    return t;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 1 ? 0 : (s.vars[0] == 2 ? 1 : -1);

  static const _valX = [0, 100, 450, 900, 400, 200, 200, 0];
  static const _valJ = [0, 200, 700, 1300, 500, 300, 300, 0];

  @override
  int moveOrder(GridState s, int m) {
    if (m == kPass) return -1000;
    final vals = janggi ? _valJ : _valX;
    final victim = s.cells[mvTo(m)];
    if (victim < 0) return 0;
    return vals[eType(victim)] * 10 - vals[eType(s.cells[mvFrom(m)])];
  }

  @override
  double evaluate(GridState s, int player) {
    final vals = janggi ? _valJ : _valX;
    var v = 0.0;
    for (var i = 0; i < s.cells.length; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      final o = eColor(x), t = eType(x);
      final r = i ~/ cols, c = i % cols;
      var val = vals[t].toDouble();
      if (t == xS) {
        final adv = o == 0 ? 6 - r : r - 3;
        val += adv * (janggi ? 12 : 25);
        if (!janggi && (o == 0 ? r <= 4 : r >= 5)) val += 80;
      }
      if (t == xH || t == xC || t == xR) val += (4 - (c - 4).abs()) * 6;
      v += o == player ? val : -val;
    }
    if (janggi) v += player == 1 ? 150 : -150;
    return v / 10;
  }

  @override
  String status(GridState s, String lang) {
    if (!janggi) return '';
    final b = points(s, 1) * 10 + 15;
    return '${points(s, 0)}  ·  ${b ~/ 10},${b % 10}';
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}

/// Japon satrancı (n = 9) ve küçük çeşidi (n = 5). Taş kodu: renk * 16 + tür.
/// Türler: 1 piyon, 2 mızrak, 3 at, 4 gümüş, 5 altın, 6 fil, 7 kale, 8 şah,
/// 9..12 terfili piyon/mızrak/at/gümüş, 13 terfili fil, 14 terfili kale.
/// Eldeki taşlar tahtanın ardındaki hücrelerde sayı olarak tutulur:
/// hücre n*n + oyuncu*7 + (tür - 1). Elden koyma hamlesi o hücreden yapılır.
const sP = 1, sL = 2, sN = 3, sS = 4, sG = 5, sB = 6, sR = 7, sK = 8;
int sColor(int v) => v < 0 ? -1 : v ~/ 16;
int sType(int v) => v < 0 ? 0 : v % 16;
int sBase(int t) => t <= 8 ? t : const [0, 1, 2, 3, 4, 6, 7][t - 8];
int sPromote(int t) => const [0, 9, 10, 11, 12, 0, 13, 14, 0][t];

class ShogiRules extends BoardRules<GridState> {
  final int n;
  const ShogiRules([this.n = 9]);

  @override
  String get id => n == 9 ? 'shogi' : 'shogi-5';

  @override
  int get maxPly => n == 9 ? 320 : 200;

  @override
  double get decisive => 130;

  int get zone => n == 9 ? 3 : 1;
  List<int> get handTypes => n == 9 ? const [sR, sB, sG, sS, sN, sL, sP] : const [sR, sB, sG, sS, sP];
  int handCell(int p, int t) => n * n + p * 7 + t - 1;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(n, n, List.filled(n * n + 14, -1), List.filled(8, 0));
    for (var i = n * n; i < s.cells.length; i++) {
      s.cells[i] = 0;
    }
    if (n == 5) {
      const back = [sK, sG, sS, sB, sR];
      for (var c = 0; c < 5; c++) {
        s.cells[20 + c] = back[c];
        s.cells[4 - c] = 16 + back[c];
      }
      s.cells[15] = sP;
      s.cells[9] = 16 + sP;
      return s;
    }
    const back = [sL, sN, sS, sG, sK, sG, sS, sN, sL];
    for (var c = 0; c < 9; c++) {
      s.cells[72 + c] = back[c];
      s.cells[c] = 16 + back[c];
      s.cells[54 + c] = sP;
      s.cells[18 + c] = 16 + sP;
    }
    s.cells[63 + 1] = sB;
    s.cells[63 + 7] = sR;
    s.cells[9 + 1] = 16 + sR;
    s.cells[9 + 7] = 16 + sB;
    return s;
  }

  static const _gold = [(0, 1), (1, 1), (-1, 1), (1, 0), (-1, 0), (0, -1)];
  static const _silver = [(0, 1), (1, 1), (-1, 1), (1, -1), (-1, -1)];
  static const _king = [(0, 1), (1, 1), (-1, 1), (1, 0), (-1, 0), (0, -1), (1, -1), (-1, -1)];
  static const _orth = [(0, 1), (1, 0), (-1, 0), (0, -1)];
  static const _diag = [(1, 1), (-1, 1), (1, -1), (-1, -1)];

  bool _in(int c, int r) => c >= 0 && r >= 0 && c < n && r < n;

  /// [p] için ileri sırasından uzaklık: 0 en uç sıra.
  int depth(int r, int p) => p == 0 ? r : n - 1 - r;

  /// Taşın tahtadaki yalancı-yasal varışları.
  void steps(GridState s, int i, void Function(int to) add) {
    final v = s.cells[i];
    final p = sColor(v), t = sType(v);
    final c0 = i % n, r0 = i ~/ n;
    final f = p == 0 ? -1 : 1;
    bool tryTo(int dc, int fdr) {
      final c = c0 + dc, r = r0 + fdr * f;
      if (!_in(c, r)) return false;
      final o = sColor(s.cells[r * n + c]);
      if (o != p) add(r * n + c);
      return o < 0;
    }

    void slide(List<(int, int)> dirs) {
      for (final (dc, dr) in dirs) {
        var k = 1;
        while (tryTo(dc * k, dr * k)) {
          k++;
        }
      }
    }

    switch (t) {
      case sP:
        tryTo(0, 1);
      case sL:
        slide(const [(0, 1)]);
      case sN:
        tryTo(1, 2);
        tryTo(-1, 2);
      case sS:
        for (final (dc, dr) in _silver) {
          tryTo(dc, dr);
        }
      case sK:
        for (final (dc, dr) in _king) {
          tryTo(dc, dr);
        }
      case sB:
        slide(_diag);
      case sR:
        slide(_orth);
      case 13:
        slide(_diag);
        for (final (dc, dr) in _orth) {
          tryTo(dc, dr);
        }
      case 14:
        slide(_orth);
        for (final (dc, dr) in _diag) {
          tryTo(dc, dr);
        }
      default: // altın ve altın gibi oynayan terfililer
        for (final (dc, dr) in _gold) {
          tryTo(dc, dr);
        }
    }
  }

  int kingSq(GridState s, int p) {
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] == p * 16 + sK) return i;
    }
    return -1;
  }

  /// [by] oyuncusunun bir taşı [sq] karesine vurabiliyor mu (geriye bakarak).
  bool attacked(GridState s, int sq, int by) {
    final c0 = sq % n, r0 = sq ~/ n;
    final f = by == 0 ? -1 : 1;
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dc == 0 && dr == 0) continue;
        final c = c0 + dc, r = r0 + dr;
        if (!_in(c, r)) continue;
        final v = s.cells[r * n + c];
        if (sColor(v) != by) continue;
        // Saldıranın kendi ileri yönüne göre hamle vektörü.
        final vc = -dc, vf = -dr * f;
        final t = sType(v);
        final hits = switch (t) {
          sK => true,
          sP || sL => vc == 0 && vf == 1,
          sS => vf == 1 || (vf == -1 && vc != 0),
          sB || sR || sN => false,
          13 => vc == 0 || vf == 0,
          14 => vc != 0 && vf != 0,
          _ => vf >= 0 || vc == 0,
        };
        if (hits) return true;
      }
    }
    for (final dc in const [-1, 1]) {
      final c = c0 + dc, r = r0 - 2 * f;
      if (_in(c, r) && s.cells[r * n + c] == by * 16 + sN) return true;
    }
    for (var dr = -1; dr <= 1; dr++) {
      for (var dc = -1; dc <= 1; dc++) {
        if (dc == 0 && dr == 0) continue;
        var c = c0 + dc, r = r0 + dr;
        while (_in(c, r)) {
          final v = s.cells[r * n + c];
          if (v >= 0) {
            if (sColor(v) == by) {
              final t = sType(v);
              final diag = dc != 0 && dr != 0;
              if (diag && (t == sB || t == 13)) return true;
              if (!diag && (t == sR || t == 14)) return true;
              if (t == sL && dc == 0 && dr == -f) return true;
            }
            break;
          }
          c += dc;
          r += dr;
        }
      }
    }
    return false;
  }

  bool inCheck(GridState s, int p) {
    final k = kingSq(s, p);
    return k < 0 || attacked(s, k, 1 - p);
  }

  /// Bu taş bu sırada bir daha oynayamaz mı (zorunlu terfi / koyma yasağı).
  bool _dead(int t, int r, int p) {
    final d = depth(r, p);
    if (t == sP || t == sL) return d == 0;
    if (t == sN) return d <= 1;
    return false;
  }

  List<int> _pseudo(GridState s, int p) {
    final out = <int>[];
    for (var i = 0; i < n * n; i++) {
      final v = s.cells[i];
      if (sColor(v) != p) continue;
      final t = sType(v);
      steps(s, i, (to) {
        final canPromote = sPromote(t) > 0 && (depth(i ~/ n, p) < zone || depth(to ~/ n, p) < zone);
        if (canPromote) out.add(mv(i, to, 1));
        if (!canPromote || !_dead(t, to ~/ n, p)) out.add(mv(i, to));
      });
    }
    for (final t in handTypes) {
      final h = handCell(p, t);
      if (s.cells[h] <= 0) continue;
      for (var to = 0; to < n * n; to++) {
        if (s.cells[to] >= 0) continue;
        if (_dead(t, to ~/ n, p)) continue;
        if (t == sP) {
          var twice = false;
          for (var r = 0; r < n && !twice; r++) {
            if (s.cells[r * n + to % n] == p * 16 + sP) twice = true;
          }
          if (twice) continue;
        }
        out.add(mv(h, to));
      }
    }
    return out;
  }

  void _move(GridState s, int m) {
    final p = s.turn;
    final f = mvFrom(m), to = mvTo(m);
    if (f >= n * n) {
      s.cells[f]--;
      s.cells[to] = p * 16 + (f - n * n - p * 7 + 1);
    } else {
      final cap = s.cells[to];
      if (cap >= 0) s.cells[handCell(p, sBase(sType(cap)))]++;
      final t = sType(s.cells[f]);
      s.cells[to] = p * 16 + (mvExtra(m) == 1 ? sPromote(t) : t);
      s.cells[f] = -1;
    }
    s.last = to;
  }

  List<int> _legal(GridState s, [bool any = false]) {
    final p = s.turn;
    final out = <int>[];
    for (final m in _pseudo(s, p)) {
      final c = s.copy();
      _move(c, m);
      if (inCheck(c, p)) continue;
      if (mvFrom(m) == handCell(p, sP) && inCheck(c, 1 - p)) {
        // Piyon koyarak mat yasak.
        c.turn = 1 - p;
        if (_legal(c, true).isEmpty) continue;
      }
      out.add(m);
      if (any) break;
    }
    return out;
  }

  @override
  List<int> moves(GridState s) => isOver(s) ? const [] : _legal(s);

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    _move(s, m);
    s.ply++;
    s.turn = 1 - p;
    if (_legal(s, true).isEmpty) {
      s.vars[0] = p + 1;
    } else if (s.ply >= maxPly) {
      s.vars[0] = 3;
    }
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 1 ? 0 : (s.vars[0] == 2 ? 1 : -1);

  static const _val = [0, 100, 300, 350, 450, 500, 800, 1000, 0, 520, 500, 500, 500, 1100, 1300];

  @override
  int moveOrder(GridState s, int m) {
    var v = mvExtra(m) * 300;
    final f = mvFrom(m);
    if (f >= n * n) return v - 50;
    final cap = s.cells[mvTo(m)];
    if (cap >= 0) v += _val[sType(cap)] * 10 - _val[sType(s.cells[f])];
    return v;
  }

  @override
  double evaluate(GridState s, int player) {
    var v = 0.0;
    for (var i = 0; i < n * n; i++) {
      final x = s.cells[i];
      if (x < 0) continue;
      final o = sColor(x), t = sType(x);
      var val = _val[t].toDouble();
      if (t == sP || t == sS || t == sG) val += (n - 1 - depth(i ~/ n, o)) * 4;
      v += o == player ? val : -val;
    }
    for (final p in const [0, 1]) {
      for (final t in handTypes) {
        final k = s.cells[handCell(p, t)];
        if (k > 0) v += (p == player ? 1 : -1) * k * _val[t] * 1.1;
      }
    }
    return v / 10;
  }

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
