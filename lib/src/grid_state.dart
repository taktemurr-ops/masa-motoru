import 'board_game.dart';

/// Kare ızgara üzerinde taşlar: hücre -1 boş, 0/1 oyuncu taşı (oyuna göre
/// başka kodlar da olabilir: dama, satranç taşları…).
class GridState extends BoardState {
  final int cols, rows;
  final List<int> cells;

  /// Oyuna özel sayılar (skor, alınan taş, kazanan…).
  final List<int> vars;
  GridState(this.cols, this.rows, this.cells, [List<int>? vars]) : vars = vars ?? List.filled(8, 0);

  int at(int c, int r) => cells[r * cols + c];
  bool inside(int c, int r) => c >= 0 && r >= 0 && c < cols && r < rows;

  @override
  GridState copy() => copyBase(GridState(cols, rows, List.of(cells), List.of(vars)));

  @override
  Map<String, Object?> toJson() => {...baseJson(), 'c': cols, 'r': rows, 'g': cells, 'v': vars};

  static GridState read(Map<String, dynamic> j) {
    final s = GridState((j['c'] as num).toInt(), (j['r'] as num).toInt(), intList(j['g']), intList(j['v']));
    s.readBase(j);
    return s;
  }
}
