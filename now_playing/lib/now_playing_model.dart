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

  void start() {
    _sub = _events.receiveBroadcastStream().listen(_onEvent, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
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
  Future<void> refresh() => _call('refresh');
  Future<void> openAccessSettings() => _call('openAccessSettings');

  Future<void> _call(String method) async {
    try {
      await _control.invokeMethod(method);
    } catch (_) {}
  }
}
