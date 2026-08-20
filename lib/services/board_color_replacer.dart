Map<int, int> replaceBoardColorInPlace(
  List<int> cells, {
  required int source,
  required int target,
}) {
  if (source < 0 || target < 0 || source == target) return const {};
  final changes = <int, int>{};
  for (var index = 0; index < cells.length; index++) {
    if (cells[index] != source) continue;
    changes[index] = source;
    cells[index] = target;
  }
  return changes;
}
