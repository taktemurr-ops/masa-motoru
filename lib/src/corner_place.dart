import 'package:studio_core/core/rng.dart';

import 'board_game.dart';
import 'grid_state.dart';

/// 1-5 karelik 21 serbest çokkare (taban biçimleri).
const kCornerPieces = <List<(int, int)>>[
  [(0, 0)],
  [(0, 0), (1, 0)],
  [(0, 0), (1, 0), (2, 0)],
  [(0, 0), (1, 0), (0, 1)],
  [(0, 0), (1, 0), (2, 0), (3, 0)],
  [(0, 0), (1, 0), (2, 0), (0, 1)],
  [(0, 0), (1, 0), (2, 0), (1, 1)],
  [(0, 0), (1, 0), (1, 1), (2, 1)],
  [(0, 0), (1, 0), (0, 1), (1, 1)],
  [(1, 0), (2, 0), (0, 1), (1, 1), (1, 2)], // F
  [(0, 0), (1, 0), (2, 0), (3, 0), (4, 0)], // I
  [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1)], // L
  [(0, 0), (1, 0), (2, 0), (2, 1), (3, 1)], // N
  [(0, 0), (1, 0), (0, 1), (1, 1), (0, 2)], // P
  [(0, 0), (1, 0), (2, 0), (1, 1), (1, 2)], // T
  [(0, 0), (2, 0), (0, 1), (1, 1), (2, 1)], // U
  [(0, 0), (0, 1), (0, 2), (1, 2), (2, 2)], // V
  [(0, 0), (0, 1), (1, 1), (1, 2), (2, 2)], // W
  [(1, 0), (0, 1), (1, 1), (2, 1), (1, 2)], // X
  [(0, 0), (1, 0), (2, 0), (3, 0), (1, 1)], // Y
  [(0, 0), (1, 0), (1, 1), (1, 2), (2, 2)], // Z
];

/// Yönelim: o = ayna * 4 + dönüş. Hücreler en küçük köşeye taşınmış ve sıralıdır.
List<(int, int)> cornerShape(int piece, int o) => _shapes[piece * 8 + o];

/// Taşın "dokunma karesi": sınır kutusunun ortasına en yakın kare.
(int, int) cornerRef(int piece, int o) => _refs[piece * 8 + o];

/// Yönelim, aynı biçimi veren daha küçük bir yönelimin tekrarı mı?
bool cornerDuplicate(int piece, int o) => _dup[piece * 8 + o];

final _shapes = [
  for (var p = 0; p < 21; p++)
    for (var o = 0; o < 8; o++) _orient(kCornerPieces[p], o),
];
final _refs = [for (final s in _shapes) _ref(s)];
final _dup = [
  for (var p = 0; p < 21; p++)
    for (var o = 0; o < 8; o++)
      [for (var q = 0; q < o; q++) _key(_shapes[p * 8 + q])].contains(_key(_shapes[p * 8 + o])),
];

String _key(List<(int, int)> s) => s.map((e) => '${e.$1},${e.$2}').join(';');

List<(int, int)> _orient(List<(int, int)> base, int o) {
  var cells = [for (final (x, y) in base) o >= 4 ? (-x, y) : (x, y)];
  for (var k = 0; k < o % 4; k++) {
    cells = [for (final (x, y) in cells) (y, -x)];
  }
  var mx = 1 << 20, my = 1 << 20;
  for (final (x, y) in cells) {
    if (x < mx) mx = x;
    if (y < my) my = y;
  }
  final out = [for (final (x, y) in cells) (x - mx, y - my)];
  out.sort((a, b) => a.$2 != b.$2 ? a.$2 - b.$2 : a.$1 - b.$1);
  return out;
}

(int, int) _ref(List<(int, int)> s) {
  var w = 0, h = 0;
  for (final (x, y) in s) {
    if (x > w) w = x;
    if (y > h) h = y;
  }
  var best = s.first;
  var bd = 1e9;
  for (final c in s) {
    final d = (c.$1 - w / 2) * (c.$1 - w / 2) + (c.$2 - h / 2) * (c.$2 - h / 2);
    if (d < bd - 1e-9) {
      bd = d;
      best = c;
    }
  }
  return best;
}

/// Köşe yerleştirme: iki oyuncu 14 × 14 tahtaya sırayla çokkare koyar. Yeni
/// taş kendi taşlarına yalnızca köşeden değmeli, kenardan asla. İlk taş
/// başlangıç noktasını örter. Hamlesi kalmayan pas geçer; ikisi de
/// geçince oyun biter ve tahtaya en çok kare koyan kazanır (bütün taşlarını
/// koyan 15, sonuncusu tek kare olursa 20 ek puan alır).
///
/// Hücreler: 0..n²-1 tahta (-1 boş, 0/1 oyuncu); ardından oyuncu başına
/// 21 hücre: taş elde mi (1/0). Hamle: from = taş+yönelim hücresi
/// [trayCell], to = taşın dokunma karesinin tahtadaki yeri.
/// vars: [0] sonuç (0 sürüyor, 1/2 kazanan + 1, 3 berabere), [1] art arda
/// pas, [2] son konan taş hücresi + 1, [3] son dokunma karesi + 1,
/// [4..5] oyuncunun son koyduğu taş.
class CornerRules extends BoardRules<GridState> {
  final int n;
  const CornerRules([this.n = 14]);

  @override
  String get id => 'kose-$n';

  @override
  int get maxPly => 120;

  int get handBase => n * n;
  int get trayBase => n * n + 42;
  int trayCell(int p, int piece, int o) => trayBase + p * 168 + piece * 8 + o;
  (int, int, int) fromTray(int cell) {
    final k = cell - trayBase;
    return (k ~/ 168, (k % 168) ~/ 8, k % 8);
  }

  int start(int p) => p == 0 ? (n - 1 - 4) * n + (n - 1 - 4) : 4 * n + 4;

  @override
  GridState initial(SeededRandom r) {
    final s = GridState(n, n, List.filled(n * n + 42, -1), List.filled(8, 0));
    for (var i = handBase; i < handBase + 42; i++) {
      s.cells[i] = 1;
    }
    return s;
  }

  bool has(GridState s, int p, int piece) => s.cells[handBase + p * 21 + piece] == 1;

  bool _touchesSide(GridState s, int c, int r, int p) {
    if (c > 0 && s.cells[r * n + c - 1] == p) return true;
    if (c < n - 1 && s.cells[r * n + c + 1] == p) return true;
    if (r > 0 && s.cells[(r - 1) * n + c] == p) return true;
    if (r < n - 1 && s.cells[(r + 1) * n + c] == p) return true;
    return false;
  }

  bool _touchesCorner(GridState s, int c, int r, int p) {
    for (final (dc, dr) in const [(1, 1), (1, -1), (-1, 1), (-1, -1)]) {
      final x = c + dc, y = r + dr;
      if (x >= 0 && y >= 0 && x < n && y < n && s.cells[y * n + x] == p) return true;
    }
    return false;
  }

  /// Taşın köşesinin oturabileceği boş kareler.
  List<int> anchors(GridState s, int p) {
    if (!s.cells.take(n * n).contains(p)) return [start(p)];
    final out = <int>[];
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] >= 0) continue;
      final c = i % n, r = i ~/ n;
      if (_touchesCorner(s, c, r, p) && !_touchesSide(s, c, r, p)) out.add(i);
    }
    return out;
  }

  List<int> _gen(GridState s, int p, {bool unique = false}) {
    final out = <int>{};
    final an = anchors(s, p);
    if (an.isEmpty) return const [];
    final ok = List<bool>.generate(n * n, (i) => s.cells[i] < 0 && !_touchesSide(s, i % n, i ~/ n, p));
    for (var piece = 0; piece < 21; piece++) {
      if (!has(s, p, piece)) continue;
      for (var o = 0; o < 8; o++) {
        final dup = cornerDuplicate(piece, o);
        if (dup && unique) continue;
        final shape = cornerShape(piece, o);
        final (rx, ry) = cornerRef(piece, o);
        for (final a in an) {
          final ac = a % n, ar = a ~/ n;
          for (final (dx, dy) in shape) {
            final ox = ac - dx, oy = ar - dy;
            var fits = true;
            for (final (x, y) in shape) {
              final c = ox + x, r = oy + y;
              if (c < 0 || r < 0 || c >= n || r >= n || !ok[r * n + c]) {
                fits = false;
                break;
              }
            }
            if (fits) out.add(mv(trayCell(p, piece, o), (oy + ry) * n + ox + rx));
          }
        }
      }
    }
    return out.toList();
  }

  @override
  List<int> moves(GridState s) {
    if (isOver(s)) return const [];
    final ms = _gen(s, s.turn);
    return ms.isEmpty ? const [kPass] : ms;
  }

  @override
  List<int> searchMoves(GridState s) {
    if (isOver(s)) return const [];
    final ms = _gen(s, s.turn, unique: true);
    if (ms.isEmpty) return const [kPass];
    // Büyük taşlar önce; arama için en çok 48 aday.
    ms.sort((a, b) => _size(b) - _size(a));
    return ms.length > 48 ? ms.sublist(0, 48) : ms;
  }

  int _size(int m) => kCornerPieces[fromTray(mvFrom(m)).$2].length;

  /// Hamlenin kapladığı tahta kareleri.
  List<int> cellsOf(int m) {
    final (_, piece, o) = fromTray(mvFrom(m));
    final (rx, ry) = cornerRef(piece, o);
    final to = mvTo(m);
    final ox = to % n - rx, oy = to ~/ n - ry;
    return [for (final (x, y) in cornerShape(piece, o)) (oy + y) * n + ox + x];
  }

  @override
  void apply(GridState s, int m) {
    final p = s.turn;
    if (m == kPass) {
      s.vars[1]++;
    } else {
      final (_, piece, _) = fromTray(mvFrom(m));
      for (final i in cellsOf(m)) {
        s.cells[i] = p;
      }
      s.cells[handBase + p * 21 + piece] = 0;
      s.vars[1] = 0;
      s.vars[2] = mvFrom(m) + 1;
      s.vars[3] = mvTo(m) + 1;
      s.vars[4 + p] = piece;
      s.last = mvTo(m);
    }
    s.ply++;
    s.turn = 1 - p;
    if (s.vars[1] >= 2) {
      final a = score(s, 0), b = score(s, 1);
      s.vars[0] = a > b ? 1 : (b > a ? 2 : 3);
    }
  }

  int score(GridState s, int p) {
    var t = 0;
    for (var i = 0; i < n * n; i++) {
      if (s.cells[i] == p) t++;
    }
    var left = 0;
    for (var k = 0; k < 21; k++) {
      left += s.cells[handBase + p * 21 + k];
    }
    if (left == 0) t += s.vars[4 + p] == 0 ? 20 : 15;
    return t;
  }

  @override
  bool isOver(GridState s) => s.vars[0] != 0;

  @override
  int winner(GridState s) => s.vars[0] == 1 ? 0 : (s.vars[0] == 2 ? 1 : -1);

  @override
  int moveOrder(GridState s, int m) => m == kPass ? -1 : _size(m) * 10;

  @override
  double evaluate(GridState s, int player) {
    final o = 1 - player;
    final mine = score(s, player) - score(s, o);
    final reach = anchors(s, player).length - anchors(s, o).length;
    return mine * 2.0 + reach * 0.6;
  }

  @override
  String status(GridState s, String lang) => '${score(s, 0)}  ·  ${score(s, 1)}';

  @override
  GridState fromJson(Map<String, dynamic> j) => GridState.read(j);
}
