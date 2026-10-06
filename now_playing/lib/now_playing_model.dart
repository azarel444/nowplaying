import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'lyrics.dart';
import 'net.dart';
import 'palette.dart';

/// Talks to the Kotlin side (MainActivity) which listens to the active
/// Android media session, whichever player app owns it.
class NowPlayingModel extends ChangeNotifier {
  static const _events = EventChannel('nowplaying/stream');
  static const _control = MethodChannel('nowplaying/control');
  static const _fftEvents = EventChannel('nowplaying/fft');

  bool accessGranted = true; // assume yes until Android says otherwise
  bool visualizerEnabled = true;
  bool artLookupEnabled = true;
  bool lyricsEnabled = false;
  List<LyricLine>? lyrics;
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
  int _lyricsToken = 0;
  Timer? _netTimer;
  bool? _sentBoot;
  bool? _sentMusic;
  final Map<String, Uint8List> _artCache = {};
  final Map<String, List<LyricLine>?> _lyricsCache = {};
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
    if (visualizerEnabled) startVisualizer();
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
    _netTimer?.cancel();
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
        lyrics = null;
        _lyricsToken++;
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
    final changed = key != _trackKey;
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
    if (changed) {
      lyrics = null;
      _lyricsToken++;
      // Wait a moment: players often update the metadata twice in a row.
      _netTimer?.cancel();
      _netTimer = Timer(const Duration(milliseconds: 700), _runNetwork);
    }
    notifyListeners();
  }

  void _runNetwork() {
    if (title.isEmpty) return;
    if (artLookupEnabled && art == null) _lookupArt();
    if (lyricsEnabled) _fetchLyrics();
  }

  Future<void> _lookupArt() async {
    final token = _artToken;
    final k = '${artist.toLowerCase()}|${title.toLowerCase()}';
    var bytes = _artCache[k];
    bytes ??= await fetchArtwork(title, artist);
    if (bytes == null || token != _artToken) return;
    _artCache[k] = bytes;
    if (_artCache.length > 12) _artCache.remove(_artCache.keys.first);
    await _setArt(bytes);
  }

  Future<void> _fetchLyrics() async {
    final token = ++_lyricsToken;
    final k = '${artist.toLowerCase()}|${title.toLowerCase()}';
    List<LyricLine>? found;
    if (_lyricsCache.containsKey(k)) {
      found = _lyricsCache[k];
    } else {
      found = await fetchSyncedLyrics(title, artist, durationMs);
      _lyricsCache[k] = found;
      if (_lyricsCache.length > 12) _lyricsCache.remove(_lyricsCache.keys.first);
    }
    if (token != _lyricsToken) return;
    lyrics = found;
    notifyListeners();
  }

  /// Index of the lyric line being sung at [ms], or -1 before the first.
  int lyricIndexAt(int ms) {
    final l = lyrics;
    if (l == null || l.isEmpty) return -1;
    var lo = 0, hi = l.length - 1, ans = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (l[mid].ms <= ms) {
        ans = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return ans;
  }

  void setLyricsEnabled(bool on) {
    lyricsEnabled = on;
    if (on) {
      if (title.isNotEmpty) _fetchLyrics();
    } else {
      lyrics = null;
      _lyricsToken++;
      notifyListeners();
    }
  }

  void setArtLookup(bool on) {
    artLookupEnabled = on;
    if (on && title.isNotEmpty && art == null) _lookupArt();
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
    if (visualizerEnabled) await _call('startVisualizer');
  }

  void setVisualizer(bool on) {
    visualizerEnabled = on;
    _call(on ? 'startVisualizer' : 'stopVisualizer');
  }

  Future<void> seekTo(int ms) => _call('seekTo', ms);
  Future<void> openPlayer() => _call('openPlayer');
  Future<void> openOverlaySettings() => _call('openOverlaySettings');

  /// Tells the Kotlin side whether to launch the app at boot / when music starts.
  void setLaunchOptions(bool boot, bool music) {
    if (_sentBoot == boot && _sentMusic == music) return;
    _sentBoot = boot;
    _sentMusic = music;
    _control.invokeMethod('setLaunchOptions', {'boot': boot, 'music': music})
        .catchError((_) {});
  }

  Future<void> startVisualizer() => _call('startVisualizer');
  Future<void> openAccessSettings() => _call('openAccessSettings');

  Future<void> _call(String method, [dynamic args]) async {
    try {
      await _control.invokeMethod(method, args);
    } catch (_) {}
  }
}
