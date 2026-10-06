import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'effects.dart';
import 'now_playing_model.dart';
import 'palette.dart';
import 'settings.dart';
import 'settings_screen.dart';
import 'spectrum.dart';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final model = NowPlayingModel();
  final settings = AppSettings();
  final sim = SpectrumSim();
  final particles = ParticleField();
  final glitch = GlitchState();
  final grid = GridState();
  final _rng = math.Random();

  final _tick = ValueNotifier<int>(0); // every drawn frame (30 fps)
  final _slow = ValueNotifier<int>(0); // about 10 times a second
  late final Ticker _ticker;
  Duration _last = Duration.zero;
  double _time = 0;
  double _slowAcc = 0;

  double _nextGlitch = 5;
  double _glitchStart = -10;
  double _glitchDur = 0.35;
  double _glitchBaseY = 0.5;
  String _lastTrack = '';

  ui.Image? _noise;
  bool _night = false;
  Offset _shift = Offset.zero;
  double? _drag; // seek bar position while the finger is on it

  bool _showControls = false;
  Timer? _hideTimer;
  Timer? _clockTimer;

  ArtPalette get _palette {
    final custom = settings.accentPalette;
    if (custom != null) return custom;
    if (settings.theme == 2) return AppSettings.vaporwave;
    return model.art?.palette ?? ArtPalette.fallback;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.addListener(_onModel);
    settings.addListener(_onSettings);
    model.start();
    _ticker = createTicker(_onTick)..start();
    _clockTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(_updateClock);
    });
    makeNoiseImage().then((img) {
      if (mounted) setState(() => _noise = img);
    });
    _updateClock();
    settings.load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    model.removeListener(_onModel);
    settings.removeListener(_onSettings);
    _ticker.dispose();
    _hideTimer?.cancel();
    _clockTimer?.cancel();
    _noise?.dispose();
    model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) model.refresh();
  }

  void _onModel() {
    if (!mounted) return;
    _checkTrack();
    setState(() {});
  }

  void _onSettings() {
    if (!mounted) return;
    if (model.visualizerEnabled != settings.visualizer) {
      model.setVisualizer(settings.visualizer);
    }
    model.setArtLookup(settings.artLookup);
    if (model.lyricsEnabled != settings.lyrics) {
      model.setLyricsEnabled(settings.lyrics);
    }
    model.setLaunchOptions(settings.bootStart, settings.musicStart);
    _updateClock();
    setState(() {});
  }

  /// Night mode and the burn-in shift only need updating every so often.
  void _updateClock() {
    final now = DateTime.now();
    if (settings.night == 0) {
      _night = false;
    } else if (settings.night == 1) {
      _night = now.hour >= 20 || now.hour < 6;
    } else {
      _night = true;
    }
    if (settings.burnIn) {
      final t = now.millisecondsSinceEpoch / 60000.0;
      _shift = Offset(6 * math.sin(t * 0.7), 4 * math.sin(t * 0.5 + 1.0));
    } else {
      _shift = Offset.zero;
    }
  }

  void _checkTrack() {
    final key = model.active ? '${model.title}|${model.artist}' : '';
    if (key == _lastTrack) return;
    final hadTrack = _lastTrack.isNotEmpty;
    _lastTrack = key;
    if (hadTrack &&
        key.isNotEmpty &&
        settings.theme == 2 &&
        !settings.performance) {
      _startGlitch(0.8, 4);
    }
  }

  void _startGlitch(double dur, int bands) {
    _glitchStart = _time;
    _glitchDur = dur;
    _glitchBaseY = _rng.nextDouble();
    glitch.bands = bands;
    glitch.seed = _rng.nextInt(100000);
  }

  void _stepGlitch() {
    if (settings.theme != 2 || settings.performance) {
      glitch.active = 0;
      return;
    }
    if (_time >= _nextGlitch) {
      _startGlitch(0.35, 1);
      _nextGlitch = _time + 4 + _rng.nextDouble() * 6;
    }
    final p = (_time - _glitchStart) / _glitchDur;
    if (p < 0 || p > 1) {
      glitch.active = 0;
    } else {
      glitch.active = math.sin(p * math.pi);
      glitch.y = (_glitchBaseY + p * 0.12) % 1.0;
    }
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    if (dt < 0.029) return; // cap at about 30 fps to go easy on weak units
    _last = elapsed;
    dt = dt.clamp(0.0, 0.1).toDouble();
    _time += dt;

    sim.update(dt, model.playing, real: model.realActive ? model.fft : null);
    final bass = sim.bass;
    particles.t += dt * (0.25 + 1.2 * bass);
    grid.scroll += dt * (0.12 + 0.9 * bass);
    _stepGlitch();

    _slowAcc += dt;
    if (_slowAcc >= 0.1) {
      _slowAcc = 0;
      _slow.value++;
    }
    _tick.value++;
  }

  void _toggleTheme() {
    settings.update(() => settings.theme = (settings.theme + 1) % 3);
    _poke();
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsScreen(settings: settings, model: model),
    ));
  }

  void _poke() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 5), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _poke();
  }

  @override
  Widget build(BuildContext context) {
    final vhs = settings.theme == 2;
    final fx = vhs ? settings.effects : 0.0;
    final heavy = !settings.performance;

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v < -300) model.next();
          if (v > 300) model.previous();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _background(),
            if (vhs) ..._vhsBackdrop(fx),
            if (settings.bgEffects && settings.particles && heavy)
              RepaintBoundary(
                child: CustomPaint(
                  painter: ParticlesPainter(
                      field: particles, palette: _palette, repaint: _tick),
                ),
              ),
            if (!model.accessGranted)
              _accessPrompt()
            else
              LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth, h = box.maxHeight;
                final portrait = h > w * 1.1;
                final Widget layout;
                if (vhs) {
                  layout = portrait
                      ? _vhsPortrait(w, h)
                      : _sideLayout(w, h, vhs: true);
                } else if (settings.theme == 1 && !portrait) {
                  layout = _sideLayout(w, h, vhs: false);
                } else {
                  layout = _focused(w, h, portrait);
                }
                return Transform.translate(
                  offset: _shift,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [layout, if (vhs) _osd(h)],
                  ),
                );
              }),
            if (vhs) ..._vhsOverlay(fx, heavy),
            if (_night) const ColoredBox(color: Color(0x80000000)),
            _progressLine(),
            if (_showControls) _controls(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- background

  Widget _background() {
    final art = model.art;
    final Widget child;
    if (art == null) {
      child = Container(
        key: const ValueKey('empty'),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF0B1224), Color(0xFF04050A)],
          ),
        ),
      );
    } else {
      Widget blurred = RepaintBoundary(
        child: ImageFiltered(
          imageFilter:
              ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.clamp),
          child: RawImage(
            image: art.tiny,
            fit: BoxFit.cover,
            filterQuality: FilterQuality.high,
          ),
        ),
      );
      if (settings.bgEffects && !settings.performance) {
        blurred = _drift(blurred);
      }
      child = SizedBox.expand(
        key: ValueKey(art),
        child: Stack(
          fit: StackFit.expand,
          children: [
            blurred,
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x8C000000),
                    Color(0x59000000),
                    Color(0xB3000000),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return AnimatedSwitcher(
        duration: const Duration(milliseconds: 800), child: child);
  }

  /// Slow pan and zoom. The blurred image is cached, so this only moves a
  /// finished layer around.
  Widget _drift(Widget child) {
    return AnimatedBuilder(
      animation: _tick,
      child: child,
      builder: (context, c) {
        final size = MediaQuery.of(context).size;
        final dx = math.sin(_time * 0.08) * size.width * 0.03;
        final dy = math.cos(_time * 0.06) * size.height * 0.03;
        return Transform.translate(
          offset: Offset(dx, dy),
          child: Transform.scale(scale: 1.18, child: c),
        );
      },
    );
  }

  // -------------------------------------------------------------- VHS layers

  List<Widget> _vhsBackdrop(double fx) => [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color.fromRGBO(120, 40, 200, 0.28 * fx),
                Color.fromRGBO(255, 46, 147, 0.16 * fx),
              ],
            ),
          ),
        ),
        RepaintBoundary(child: CustomPaint(painter: SunPainter(k: fx))),
        RepaintBoundary(
          child: CustomPaint(
              painter: GridPainter(state: grid, k: fx, repaint: _tick)),
        ),
      ];

  List<Widget> _vhsOverlay(double fx, bool heavy) => [
        RepaintBoundary(
          child: CustomPaint(painter: ScanlinePainter(alpha: 0.16 * fx)),
        ),
        if (heavy && _noise != null)
          RepaintBoundary(
            child: CustomPaint(
              painter:
                  GrainPainter(noise: _noise, k: 0.9 * fx, tick: _slow),
            ),
          ),
        if (heavy)
          RepaintBoundary(
            child: CustomPaint(
              painter: GlitchPainter(g: glitch, k: fx, repaint: _tick),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 1.0,
              colors: [
                const Color(0x00000000),
                Color.fromRGBO(0, 0, 0, 0.6 * fx),
              ],
              stops: const [0.5, 1.0],
            ),
          ),
        ),
      ];

  /// Old-VCR on-screen display: PLAY / PAUSE and a tape counter.
  Widget _osd(double h) {
    final size = (h * 0.05).clamp(18.0, 40.0).toDouble();
    return Positioned(
      left: size,
      top: size * 0.8,
      child: AnimatedBuilder(
        animation: _slow,
        builder: (context, _) {
          final blinkOff = !model.playing && (_slow.value ~/ 5) % 2 == 1;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: blinkOff ? 0.0 : 1.0,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(model.playing ? Icons.play_arrow : Icons.pause,
                        size: size * 1.1, color: Colors.white),
                    SizedBox(width: size * 0.2),
                    _osdText(model.playing ? 'PLAY' : 'PAUSE', size),
                  ],
                ),
              ),
              SizedBox(height: size * 0.15),
              _osdText(_tape(model.positionMs), size * 0.8),
            ],
          );
        },
      ),
    );
  }

  Text _osdText(String s, double size) => Text(
        s,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: size,
          fontWeight: FontWeight.w700,
          letterSpacing: size * 0.12,
          color: Colors.white,
          shadows: const [
            Shadow(color: Color(0xCCFF2E93), offset: Offset(-2, 0)),
            Shadow(color: Color(0xCC05D9FF), offset: Offset(2, 0)),
          ],
        ),
      );

  String _tape(int ms) {
    final s = ms ~/ 1000;
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final sec = (s % 60).toString().padLeft(2, '0');
    return '${s ~/ 3600}:$m:$sec';
  }

  // ------------------------------------------------------------------- themes

  Widget _focused(double w, double h, bool portrait) {
    final barsMode = settings.vizStyle == 1;
    var art = portrait
        ? math.min(h * 0.36, w * 0.54)
        : math.min(h * 0.48, w * 0.34);
    if (barsMode) art *= 0.88;
    final outer = art * 0.86; // ring radius including the tallest bars
    final cx = w / 2;
    final cy = (portrait ? h * 0.07 : h * 0.02) + outer;
    return Stack(
      children: [
        if (settings.visualizer && !barsMode)
          Positioned(
            left: cx - outer,
            top: cy - outer,
            width: outer * 2,
            height: outer * 2,
            child: RepaintBoundary(
              child: CustomPaint(
                painter: RingPainter(
                  sim: sim,
                  palette: _palette,
                  innerRadius: art * 0.66,
                  maxLen: art * 0.2,
                  count: settings.barCount,
                  gain: settings.sensitivity,
                  repaint: _tick,
                ),
              ),
            ),
          ),
        Positioned(
          left: cx - art / 2,
          top: cy - art / 2,
          width: art,
          child: _artWithReflection(art),
        ),
        if (settings.visualizer && barsMode)
          Positioned(
            left: w * 0.1,
            right: w * 0.1,
            bottom: h * 0.16,
            height: h * 0.12,
            child: _bars(h * 0.12),
          ),
        Positioned(
          left: w * 0.1,
          right: w * 0.1,
          bottom: h * 0.045,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _title(h * 0.062, Alignment.center, false),
              SizedBox(height: h * 0.012),
              if (_hasLyrics)
                _lyricLine(h * 0.03, Alignment.center)
              else
                _artist(h * 0.026, Alignment.center, false),
            ],
          ),
        ),
      ],
    );
  }

  /// Art on the left, text and bars on the right. Used by Side by Side and
  /// VHS. The art card itself is centered on the screen; its reflection is
  /// allowed to run down toward the bottom edge.
  Widget _sideLayout(double w, double h, {required bool vhs}) {
    final artSize = math.min(h * 0.6, w * 0.34);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: w * 0.07),
        _artCentered(artSize, vhs: vhs),
        SizedBox(width: w * 0.05),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _artist(h * 0.032, Alignment.centerLeft, vhs),
              SizedBox(height: h * 0.012),
              _title(h * 0.085, Alignment.centerLeft, vhs),
              if (model.album.isNotEmpty && model.album != model.title) ...[
                SizedBox(height: h * 0.012),
                _fit(_albumText(h * 0.028), Alignment.centerLeft),
              ],
              if (_hasLyrics) ...[
                SizedBox(height: h * 0.03),
                _lyricBlock(h, Alignment.centerLeft, vhs: vhs),
                SizedBox(height: h * 0.02),
                _bars(h * 0.2, blocky: vhs),
              ] else ...[
                SizedBox(height: h * 0.07),
                _bars(h * 0.3, blocky: vhs),
              ],
            ],
          ),
        ),
        SizedBox(width: w * 0.05),
      ],
    );
  }

  Widget _vhsPortrait(double w, double h) {
    final s = math.min(h * 0.32, w * 0.54);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: w * 0.08),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _artWithReflection(s, vhs: true),
          SizedBox(height: h * 0.03),
          _title(h * 0.04, Alignment.center, true),
          SizedBox(height: h * 0.01),
          _artist(h * 0.018, Alignment.center, true),
          if (_hasLyrics) ...[
            SizedBox(height: h * 0.02),
            _lyricBlock(h * 0.6, Alignment.center, vhs: true),
          ],
          SizedBox(height: h * 0.04),
          _bars(h * 0.14, blocky: true),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ lyrics

  bool get _hasLyrics =>
      settings.lyrics && (model.lyrics?.isNotEmpty ?? false);

  String _lyricAt(int delta) {
    final l = model.lyrics;
    if (l == null || l.isEmpty) return '';
    final k = model.lyricIndexAt(model.positionMs + 150) + delta;
    if (k < 0 || k >= l.length) return '';
    return l[k].text.isEmpty ? '...' : l[k].text;
  }

  /// Current line only (used by the Focused theme).
  Widget _lyricLine(double size, Alignment a) {
    return AnimatedBuilder(
      animation: _slow,
      builder: (context, _) => _fit(
        Text(
          _lyricAt(0),
          maxLines: 1,
          style: TextStyle(
            fontSize: size,
            fontWeight: FontWeight.w400,
            color: Colors.white.withOpacity(0.85),
          ),
        ),
        a,
      ),
    );
  }

  /// Current line large, next line small. Fixed height so nothing jumps.
  Widget _lyricBlock(double h, Alignment a, {required bool vhs}) {
    final cross =
        a == Alignment.center ? CrossAxisAlignment.center : CrossAxisAlignment.start;
    return SizedBox(
      height: h * 0.12,
      child: AnimatedBuilder(
        animation: _slow,
        builder: (context, _) {
          final i = model.lyricIndexAt(model.positionMs + 150);
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: Column(
              key: ValueKey<int>(i),
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: cross,
              children: [
                _fit(
                  Text(
                    _lyricAt(0),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: h * 0.04,
                      fontWeight: FontWeight.w400,
                      color: Colors.white,
                      shadows: vhs
                          ? const [
                              Shadow(
                                  color: Color(0x99FF2E93), offset: Offset(-1.5, 0)),
                              Shadow(
                                  color: Color(0x9905D9FF), offset: Offset(1.5, 0)),
                            ]
                          : null,
                    ),
                  ),
                  a,
                ),
                SizedBox(height: h * 0.008),
                _fit(
                  Text(
                    _lyricAt(1),
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: h * 0.026,
                      color: Colors.white38,
                    ),
                  ),
                  a,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _bars(double height, {bool blocky = false}) {
    if (!settings.visualizer) return SizedBox(height: height);
    return SizedBox(
      height: height,
      width: double.infinity,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: BarsPainter(
            sim: sim,
            palette: _palette,
            count: settings.barCount,
            gain: settings.sensitivity,
            blocky: blocky,
            repaint: _tick,
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------------- pieces

  String get _titleStr => model.active && model.title.isNotEmpty
      ? model.title
      : 'Nothing playing';

  String get _artistStr => model.active
      ? model.artist
      : 'Start music in any player app';

  Text _titleText(double size, {Color? color}) => Text(
        _titleStr,
        maxLines: 1,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w300,
          color: color ?? Colors.white,
          height: 1.1,
        ),
      );

  Text _artistText(double size, {Color? color}) => Text(
        _artistStr.toUpperCase(),
        maxLines: 1,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w400,
          letterSpacing: size * 0.38,
          color: color ?? Colors.white.withOpacity(0.62),
        ),
      );

  Text _albumText(double size) => Text(
        model.album.toUpperCase(),
        maxLines: 1,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w400,
          letterSpacing: size * 0.38,
          color: Colors.white.withOpacity(0.45),
        ),
      );

  Widget _title(double size, Alignment a, bool vhs) => _fit(
        vhs ? _split((c) => _titleText(size, color: c)) : _titleText(size),
        a,
      );

  Widget _artist(double size, Alignment a, bool vhs) => _fit(
        vhs
            ? _split((c) => _artistText(size, color: c), main: Colors.white70)
            : _artistText(size),
        a,
      );

  /// RGB split: a pink and a cyan ghost behind the sharp text.
  Widget _split(Widget Function(Color) build, {Color main = Colors.white}) {
    final d = 1.0 + 2.5 * settings.effects;
    return Stack(
      children: [
        Transform.translate(
            offset: Offset(-d, 0), child: build(const Color(0x99FF2E93))),
        Transform.translate(
            offset: Offset(d, 0), child: build(const Color(0x9905D9FF))),
        build(main),
      ],
    );
  }

  Widget _fit(Widget child, Alignment align) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align,
        child: child,
      );

  /// The clipped album image (or a placeholder), keyed so it can crossfade.
  Widget _artContent(double s) {
    final art = model.art;
    final radius = s * 0.07;
    return ClipRRect(
      key: ValueKey<Object>(art ?? 'placeholder'),
      borderRadius: BorderRadius.circular(radius),
      child: art == null
          ? Container(
              width: s,
              height: s,
              color: const Color(0xFF111827),
              child: Icon(Icons.music_note, size: s * 0.35, color: Colors.white24),
            )
          : Image.memory(
              art.bytes,
              width: s,
              height: s,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
            ),
    );
  }

  Widget _artCard(double s) {
    final p = _palette;
    return RepaintBoundary(
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(s * 0.07),
          border: Border.all(color: p.a.withOpacity(0.85), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: p.a.withOpacity(0.35),
                blurRadius: s * 0.12,
                spreadRadius: 1),
            BoxShadow(
                color: p.c.withOpacity(0.22),
                blurRadius: s * 0.2,
                offset: Offset(s * 0.03, 0)),
          ],
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: _artContent(s),
        ),
      ),
    );
  }

  /// Art card with a pink ghost to one side and a cyan ghost to the other.
  Widget _splitArt(double s) {
    final d = s * (0.006 + 0.014 * settings.effects);
    Widget ghost(Color c, double dx) => Transform.translate(
          offset: Offset(dx, 0),
          child: Opacity(
            opacity: 0.55,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(c, BlendMode.srcATop),
              child: _artContent(s),
            ),
          ),
        );
    return RepaintBoundary(
      child: SizedBox(
        width: s,
        height: s,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            ghost(const Color(0xFFFF2E93), -d),
            ghost(const Color(0xFF05D9FF), d),
            _artCard(s),
          ],
        ),
      ),
    );
  }

  /// Small scale-up on bass hits. Only moves a cached layer.
  Widget _pulse(Widget child) {
    if (!settings.bgEffects) return child;
    return AnimatedBuilder(
      animation: _tick,
      child: child,
      builder: (context, c) {
        final b = ((sim.bass - 0.15) / 0.6).clamp(0.0, 1.0).toDouble();
        return Transform.scale(scale: 1.0 + 0.03 * b, child: c);
      },
    );
  }

  /// Tapping the cover opens the player app that is playing.
  Widget _front(double s, bool vhs) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: model.openPlayer,
        child: _pulse(vhs ? _splitArt(s) : _artCard(s)),
      );

  /// Mirrored, fading copy of the art plus a thin contact shadow, so the
  /// card looks like it is standing on a glass surface.
  Widget _reflection(double s) {
    final h = s * 0.28;
    return SizedBox(
      width: s,
      height: h,
      child: Stack(
        children: [
          Positioned.fill(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x66FFFFFF), Color(0x00FFFFFF)],
              ).createShader(rect),
              child: ClipRect(
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: s,
                  maxWidth: s,
                  minHeight: s,
                  maxHeight: s,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    child: Transform(
                      key: ValueKey<Object>(model.art ?? 'placeholder'),
                      alignment: Alignment.center,
                      transform: Matrix4.diagonal3Values(1.0, -1.0, 1.0),
                      child: _artContent(s),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: s * 0.06,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xA6000000), Color(0x00000000)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Art with its reflection stacked underneath (used by Focused and the
  /// portrait VHS layout).
  Widget _artWithReflection(double s, {bool vhs = false}) {
    return RepaintBoundary(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _front(s, vhs),
          const SizedBox(height: 3),
          _reflection(s),
        ],
      ),
    );
  }

  /// The art card occupies exactly s x s so a Row centers the card itself.
  /// The reflection hangs below and is allowed to overflow downward.
  Widget _artCentered(double s, {required bool vhs}) {
    return SizedBox(
      width: s,
      height: s,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          _front(s, vhs),
          Positioned(left: 0, top: s + 3, width: s, child: _reflection(s)),
        ],
      ),
    );
  }

  Widget _progressLine() {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      height: 3,
      child: AnimatedBuilder(
        animation: _tick,
        builder: (context, _) {
          final d = model.durationMs;
          final f = d > 0 ? model.positionMs / d : 0.0;
          return Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: f.clamp(0.0, 1.0).toDouble(),
              child: DecoratedBox(
                decoration:
                    BoxDecoration(gradient: LinearGradient(colors: _palette.colors)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _controls() {
    Widget btn(IconData icon, double size, VoidCallback onTap) => IconButton(
          iconSize: size,
          padding: const EdgeInsets.all(14),
          color: Colors.white,
          icon: Icon(icon),
          onPressed: () {
            onTap();
            _poke();
          },
        );

    return Positioned(
      left: 0,
      right: 0,
      bottom: 28,
      child: Center(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xCC000000),
              borderRadius: BorderRadius.circular(60),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _seekBar(),
                Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                btn(Icons.view_carousel_outlined, 36, _toggleTheme),
                btn(Icons.settings, 36, _openSettings),
                const SizedBox(width: 12),
                btn(Icons.skip_previous_rounded, 56, model.previous),
                btn(
                    model.playing
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_filled,
                    76,
                    model.playPause),
                btn(Icons.skip_next_rounded, 56, model.next),
                const SizedBox(width: 16),
                AnimatedBuilder(
                  animation: _tick,
                  builder: (context, _) => Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_fmt(model.positionMs)} / ${_fmt(model.durationMs)}',
                        style:
                            const TextStyle(color: Colors.white70, fontSize: 16),
                      ),
                      Text(
                        model.realActive ? 'live audio' : 'simulated',
                        style: TextStyle(
                          color: model.realActive ? _palette.a : Colors.white38,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        AppSettings.themeNames[settings.theme],
                        style: const TextStyle(
                            color: Colors.white38, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _seekBar() {
    return AnimatedBuilder(
      animation: _tick,
      builder: (context, _) {
        final d = model.durationMs;
        final frac = d > 0 ? (model.positionMs / d).clamp(0.0, 1.0).toDouble() : 0.0;
        return SizedBox(
          width: 560,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 6,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 26),
            ),
            child: Slider(
              value: _drag ?? frac,
              activeColor: _palette.a,
              inactiveColor: Colors.white24,
              onChanged: d > 0
                  ? (v) {
                      setState(() => _drag = v);
                      _poke();
                    }
                  : null,
              onChangeEnd: d > 0
                  ? (v) {
                      model.seekTo((v * d).round());
                      _poke();
                      // Keep the thumb where it was dropped until the
                      // player reports the new position.
                      Timer(const Duration(milliseconds: 700), () {
                        if (mounted) setState(() => _drag = null);
                      });
                    }
                  : null,
            ),
          ),
        );
      },
    );
  }

  Widget _accessPrompt() {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.music_note, size: 56, color: Colors.white54),
              const SizedBox(height: 20),
              const Text(
                'Allow notification access',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w300),
              ),
              const SizedBox(height: 12),
              const Text(
                'Android only shares what is playing with apps that have '
                'notification access. Turn it on for Now Playing, then come back.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16, color: Colors.white70),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: model.openAccessSettings,
                style: ElevatedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  backgroundColor: _palette.a,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Open settings', style: TextStyle(fontSize: 18)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _fmt(int ms) {
    final s = ms ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }
}
