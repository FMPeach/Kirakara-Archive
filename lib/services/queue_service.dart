import 'package:flutter/foundation.dart';

import '../domain/queue_item.dart';
import '../domain/song.dart';

class QueueService extends ChangeNotifier {
  final List<QueueItem> _items = [];
  int _sequence = 0;

  List<QueueItem> get items => List.unmodifiable(_items);

  QueueItem addSong(Song song, {String requestedBy = '本机'}) {
    final item = QueueItem(
      id: 'queue-${++_sequence}',
      song: song,
      requestedBy: requestedBy,
      addedAt: DateTime.now(),
    );
    _items.add(item);
    notifyListeners();
    return item;
  }

  QueueItem? takeNext() {
    if (_items.isEmpty) {
      return null;
    }
    final item = _items.removeAt(0);
    notifyListeners();
    return item;
  }

  void move(int from, int to) {
    if (from < 0 || from >= _items.length || to < 0 || to >= _items.length) {
      return;
    }
    final item = _items.removeAt(from);
    _items.insert(to, item);
    notifyListeners();
  }

  QueueItem bumpToNext(Song song, {String requestedBy = '本机'}) {
    final item = QueueItem(
      id: 'queue-${++_sequence}',
      song: song,
      requestedBy: requestedBy,
      addedAt: DateTime.now(),
    );
    _items.insert(0, item);
    notifyListeners();
    return item;
  }

  void bumpItemToNext(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final item = _items.removeAt(index);
    _items.insert(0, item);
    notifyListeners();
  }

  void remove(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }
}
