/// Undo/redo stacks of immutable snapshots of type [T]. Pure, so the order of
/// restores is unit-tested; the editor stores `(annotations, image)` records.
///
/// [push] takes the state *before* a change. [undo]/[redo] take the *current*
/// state (which moves to the opposite stack) and return the state to restore,
/// or null when there is nothing to do.
class EditHistory<T> {
  EditHistory({this.maxEntries = 100});

  final int maxEntries;
  final List<T> _undo = [];
  final List<T> _redo = [];

  bool get canUndo => _undo.isNotEmpty;
  bool get canRedo => _redo.isNotEmpty;

  /// Every snapshot still held (both stacks), e.g. to find which resources
  /// are still referenced.
  Iterable<T> get entries => [..._undo, ..._redo];

  /// Records [before]; a new change invalidates redo. Returns the snapshots
  /// that were dropped (the redo stack and, past [maxEntries], the oldest
  /// undo entry) so their resources can be released.
  List<T> push(T before) {
    final dropped = <T>[..._redo];
    _redo.clear();
    _undo.add(before);
    if (_undo.length > maxEntries) dropped.add(_undo.removeAt(0));
    return dropped;
  }

  T? undo(T current) {
    if (_undo.isEmpty) return null;
    _redo.add(current);
    return _undo.removeLast();
  }

  T? redo(T current) {
    if (_redo.isEmpty) return null;
    _undo.add(current);
    return _redo.removeLast();
  }
}
