import 'package:flutter/foundation.dart';

enum CastState {
  idle,
  searching,
  casting,
}

class CastService extends ChangeNotifier {
  CastState _state = CastState.idle;
  String? _targetName;

  CastState get state => _state;
  String? get targetName => _targetName;
  bool get isCasting => _state == CastState.casting;

  Future<void> startMockCast({String targetName = '客厅电视'}) async {
    _state = CastState.searching;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    _targetName = targetName;
    _state = CastState.casting;
    notifyListeners();
  }

  Future<void> stopCast() async {
    _targetName = null;
    _state = CastState.idle;
    notifyListeners();
  }
}
