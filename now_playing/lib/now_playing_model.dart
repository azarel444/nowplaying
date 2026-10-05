import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'palette.dart';

/// Talks to the Kotlin side (MainActivity) which listens to the active
/// Android media session, whichever player app owns it.
class NowPlayingModel extends ChangeNotifier {
  static const _events = EventChannel('nowplaying/stream');
  static const _control = MethodChannel('nowplaying/control');
  static const _fftEvents = EventChannel('nowplaying/fft');

  bool accessGranted = true; // assume yes until Android says otherwise
  bool active = false;
  bool playing = false;
  String title = '';
  String artist = '';
  String album = '';
  int durationMs = 0;
  ArtAssets? art;

  int _posMs = 0;
  double _speed = 1.0;
  DateTime _stamp = DateTime.now();
  String _trackKey = '';
  int _artToken = 0;
  StreamSubscription? _sub;
  StreamSubscription? _fftSub;

  /// Latest frequency bands from the audio output (96 values, 0..255).
  Uint8List? fft;
  DateTime _realAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// True while the device is giving us real audio data. When it stops
  /// (older/newer Android blocking it, or silence) the screen falls back to
  /// the simulated visualizer.
  bool get realActive =>
      fft != null && DateTime.now().difference(_realAt).inMilliseconds < 1500;

  void start() {
    _sub = _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
    _fftSub =
        _fftEvents.receiveBroadcastStream().listen(_onFft, onError: (_) {});
    startVisualizer();
  }

  void _onFft(dynamic e) {
    if (e is! Uint8List) return;
    fft = e;
    var sum = 0;
    for (final b in e) {
      sum += b;
    }
    if (sum > 30) _realAt = DateTime.now();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _fftSub?.cancel();
    super.dispose();
  }

  /// Current position, interpolated between updates from the player.
  int get positionMs {
    var p = _posMs;
    if (playing) {
      p += (DateTime.now().difference(_stamp).inMilliseconds * _speed).round();
    }
    if (durationMs > 0 && p > durationMs) p = durationMs;
    return p < 0 ? 0 : p;
  }

  void _onEvent(dynamic e) {
    final m = Map<String, dynamic>.from(e as Map);
    accessGranted = m['access'] == true;
    active = m['active'] == true;

    if (!accessGranted || !active) {
      playing = false;
      if (!active) {
        title = '';
        artist = '';
        album = '';
        durationMs = 0;
        _trackKey = '';
        _artToken++;
        art = null;
      }
      notifyListeners();
      return;
    }

    playing = m['playing'] == true;
    title = (m['title'] as String?) ?? '';
    artist = (m['artist'] as String?) ?? '';
    album = (m['album'] as String?) ?? '';
    durationMs = (m['duration'] as num?)?.toInt() ?? 0;
    _posMs = (m['position'] as num?)?.toInt() ?? 0;
    _speed = (m['speed'] as num?)?.toDouble() ?? 1.0;
    _stamp = DateTime.now();

    final key = '$title|$artist|$album|$durationMs';
    final artBytes = m['art'];
    if (artBytes is Uint8List) {
      if (art == null || !listEquals(art!.bytes, artBytes)) {
        _setArt(artBytes);
      }
    } else if (key != _trackKey) {
      _artToken++;
      art = null;
    }
    _trackKey = key;
    notifyListeners();
  }

  Future<void> _setArt(Uint8List bytes) async {
    final token = ++_artToken;
    final loaded = await ArtAssets.load(bytes);
    if (token != _artToken) return;
    art = loaded;
    notifyListeners();
  }

  Future<void> playPause() => _call('playPause');
  Future<void> next() => _call('next');
  Future<void> previous() => _call('previous');
  Future<void> refresh() async {
    await _call('refresh');
    await _call('startVisualizer');
  }

  Future<void> startVisualizer() => _call('startVisualizer');
  Future<void> openAccessSettings() => _call('openAccessSettings');

  Future<void> _call(String method) async {
    try {
      await _control.invokeMethod(method);
    } catch (_) {}
  }
}
