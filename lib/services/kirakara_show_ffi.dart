import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

// ── C type aliases ────────────────────────────────────────────────

typedef ShowHostHandle = Pointer<Void>;

typedef CreateNative = ShowHostHandle Function();
typedef DestroyNative = Void Function(ShowHostHandle);
typedef LoadNative = Bool Function(
    ShowHostHandle, Pointer<Utf16>, Pointer<Utf16>);
typedef PlayNative = Void Function(ShowHostHandle);
typedef PauseNative = Void Function(ShowHostHandle);
typedef StopNative = Void Function(ShowHostHandle);
typedef SeekNative = Void Function(ShowHostHandle, Double);
typedef ResizeNative = Void Function(ShowHostHandle, Uint32, Uint32);
typedef RenderNative = Void Function(ShowHostHandle);
typedef ReadFrameNative = Uint32 Function(
    ShowHostHandle, Pointer<Uint8>, Uint32);
typedef GetPositionNative = Double Function(ShowHostHandle);
typedef GetDurationNative = Double Function(ShowHostHandle);
typedef GetStateNative = Int Function(ShowHostHandle);
typedef GetWidthNative = Uint32 Function(ShowHostHandle);
typedef GetHeightNative = Uint32 Function(ShowHostHandle);

// ── Dart function signatures ──────────────────────────────────────

typedef _Create = ShowHostHandle Function();
typedef _Destroy = void Function(ShowHostHandle);
typedef _Load = bool Function(ShowHostHandle, Pointer<Utf16>, Pointer<Utf16>);
typedef _Play = void Function(ShowHostHandle);
typedef _Pause = void Function(ShowHostHandle);
typedef _Stop = void Function(ShowHostHandle);
typedef _Seek = void Function(ShowHostHandle, double);
typedef _Resize = void Function(ShowHostHandle, int, int);
typedef _Render = void Function(ShowHostHandle);
typedef _ReadFrame = int Function(ShowHostHandle, Pointer<Uint8>, int);
typedef _GetPosition = double Function(ShowHostHandle);
typedef _GetDuration = double Function(ShowHostHandle);
typedef _GetState = int Function(ShowHostHandle);
typedef _GetWidth = int Function(ShowHostHandle);
typedef _GetHeight = int Function(ShowHostHandle);

// ── KirakaraShowFFI ───────────────────────────────────────────────

class KirakaraShowFFI {
  KirakaraShowFFI({String? dllPath})
      : _dylib = DynamicLibrary.open(dllPath ?? _defaultDllPath()) {
    _bind();
  }

  final DynamicLibrary _dylib;
  late final ShowHostHandle _handle;

  late final _Create _create;
  late final _Destroy _destroy;
  late final _Load _load;
  late final _Play _play;
  late final _Pause _pause;
  late final _Stop _stop;
  late final _Seek _seek;
  late final _Resize _resize;
  late final _Render _render;
  late final _ReadFrame _readFrame;
  late final _GetPosition _getPosition;
  late final _GetDuration _getDuration;
  late final _GetState _getState;
  late final _GetWidth _getWidth;
  late final _GetHeight _getHeight;

  int _width = 0;
  int _height = 0;
  Uint8List? _frameBuffer;

  int get width => _width;
  int get height => _height;

  void _bind() {
    _create = _dylib.lookupFunction<CreateNative, _Create>('show_host_create');
    _destroy =
        _dylib.lookupFunction<DestroyNative, _Destroy>('show_host_destroy');
    _load = _dylib.lookupFunction<LoadNative, _Load>('show_host_load');
    _play = _dylib.lookupFunction<PlayNative, _Play>('show_host_play');
    _pause = _dylib.lookupFunction<PauseNative, _Pause>('show_host_pause');
    _stop = _dylib.lookupFunction<StopNative, _Stop>('show_host_stop');
    _seek = _dylib.lookupFunction<SeekNative, _Seek>('show_host_seek');
    _resize =
        _dylib.lookupFunction<ResizeNative, _Resize>('show_host_resize');
    _render =
        _dylib.lookupFunction<RenderNative, _Render>('show_host_render');
    _readFrame = _dylib.lookupFunction<ReadFrameNative, _ReadFrame>(
        'show_host_read_frame');
    _getPosition = _dylib.lookupFunction<GetPositionNative, _GetPosition>(
        'show_host_get_position');
    _getDuration = _dylib.lookupFunction<GetDurationNative, _GetDuration>(
        'show_host_get_duration');
    _getState = _dylib.lookupFunction<GetStateNative, _GetState>(
        'show_host_get_state');
    _getWidth = _dylib.lookupFunction<GetWidthNative, _GetWidth>(
        'show_host_get_width');
    _getHeight = _dylib.lookupFunction<GetHeightNative, _GetHeight>(
        'show_host_get_height');

    _handle = _create();
  }

  bool load(String videoPath, String lyricPath) {
    final video = videoPath.toNativeUtf16();
    final lyric = lyricPath.toNativeUtf16();
    try {
      final ok = _load(_handle, video, lyric);
      if (ok) {
        _width = _getWidth(_handle);
        _height = _getHeight(_handle);
        _frameBuffer = Uint8List(_width * _height * 4);
      }
      return ok;
    } finally {
      calloc.free(video);
      calloc.free(lyric);
    }
  }

  void play() => _play(_handle);
  void pause() => _pause(_handle);
  void stop() => _stop(_handle);
  void seek(double seconds) => _seek(_handle, seconds);
  void resize(int w, int h) {
    _resize(_handle, w, h);
    _width = w;
    _height = h;
    _frameBuffer = Uint8List(_width * _height * 4);
  }

  double get position => _getPosition(_handle);
  double get duration => _getDuration(_handle);
  int get state => _getState(_handle);

  /// Returns the latest rendered frame as RGBA8 bytes.
  /// Returns null if no frame is available.
  Uint8List? readFrame() {
    if (_frameBuffer == null) return null;
    final size = _frameBuffer!.length;
    final ptr = calloc<Uint8>(size);
    try {
      final bytesRead = _readFrame(_handle, ptr, size);
      if (bytesRead == 0) return null;
      return Uint8List.fromList(ptr.asTypedList(bytesRead));
    } finally {
      calloc.free(ptr);
    }
  }

  void dispose() {
    _destroy(_handle);
    _dylib.close();
  }

  static String _defaultDllPath() {
    if (Platform.isWindows) {
      // Try the build output directory first
      final exeDir = Directory(Platform.resolvedExecutable).parent;
      final buildPath = '${exeDir.path}\\show_host.dll';
      if (File(buildPath).existsSync()) return buildPath;

      // Fallback: look in the kirakara-show build directory
      const showPath = r'D:\仓库\Kirakara Show\build\bin\libshow_host.dll';
      if (File(showPath).existsSync()) return showPath;

      // Last resort: just the filename (relies on PATH)
      return 'libshow_host.dll';
    }
    throw UnsupportedError('KirakaraShowFFI is only supported on Windows');
  }
}
