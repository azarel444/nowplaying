import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'now_playing_model.dart';
import 'palette.dart';
import 'spectrum.dart';

/// 0 = Focused (art + ring), 1 = Side by side (art + spectrum)
const _kThemeKey = 'theme';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final model = NowPlayingModel();
  final sim = SpectrumSim();
  final _tick = ValueNotifier<int>(0);
  late final Ticker _ticker;
  Duration _last = Duration.zero;

  int _theme = 0;
  bool _showControls = false;
  Timer? _hideTimer;

  ArtPalette get _palette => model.art?.palette ?? ArtPalette.fallback;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    model.addListener(() => setState(() {}));
    model.start();
    _ticker = createTicker(_onTick)..start();
    _loadTheme();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _hideTimer?.cancel();
    model.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) model.refresh();
  }

  void _onTick(Duration elapsed) {
    var dt = (elapsed - _last).inMicroseconds / 1e6;
    _last = elapsed;
    dt = dt.clamp(0.0, 0.1).toDouble();
    sim.update(dt, model.playing);
    _tick.value++;
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() => _theme = prefs.getInt(_kThemeKey) ?? 0);
  }

  Future<void> _toggleTheme() async {
    setState(() => _theme = _theme == 0 ? 1 : 0);
    _poke();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kThemeKey, _theme);
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
            if (!model.accessGranted)
              _accessPrompt()
            else
              LayoutBuilder(builder: (context, box) {
                final w = box.maxWidth, h = box.maxHeight;
                final portrait = h > w * 1.1;
                return (_theme == 1 && !portrait)
                    ? _sideBySide(w, h)
                    : _focused(w, h);
              }),
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
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 800),
      child: art == null
          ? Container(
              key: const ValueKey('empty'),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF0B1224), Color(0xFF04050A)],
                ),
              ),
            )
          : SizedBox.expand(
              key: ValueKey(art),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  RepaintBoundary(
                    child: ImageFiltered(
                      imageFilter: ui.ImageFilter.blur(
                          sigmaX: 6, sigmaY: 6, tileMode: TileMode.clamp),
                      child: RawImage(
                        image: art.tiny,
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                      ),
                    ),
                  ),
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
            ),
    );
  }

  // ------------------------------------------------------------------- themes

  Widget _focused(double w, double h) {
    final artSize = math.min(h * 0.42, w * 0.30);
    final ringSide = artSize * 1.7;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: ringSide,
            height: ringSide,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size.square(ringSide),
                    painter: RingPainter(
                      sim: sim,
                      palette: _palette,
                      innerRadius: artSize * 0.6,
                      maxLen: artSize * 0.2,
                      repaint: _tick,
                    ),
                  ),
                ),
                _artCard(artSize),
              ],
            ),
          ),
          Transform.translate(
            offset: Offset(0, -ringSide * 0.07),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: w * 0.7),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _fit(_titleText(h * 0.062), Alignment.center),
                  SizedBox(height: h * 0.012),
                  _fit(_artistText(h * 0.026), Alignment.center),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sideBySide(double w, double h) {
    final artSize = math.min(h * 0.74, w * 0.34);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(width: w * 0.07),
        _artCard(artSize),
        SizedBox(width: w * 0.05),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fit(_artistText(h * 0.032), Alignment.centerLeft),
              SizedBox(height: h * 0.012),
              _fit(_titleText(h * 0.085), Alignment.centerLeft),
              if (model.album.isNotEmpty && model.album != model.title) ...[
                SizedBox(height: h * 0.012),
                _fit(_albumText(h * 0.028), Alignment.centerLeft),
              ],
              SizedBox(height: h * 0.07),
              SizedBox(
                height: h * 0.3,
                width: double.infinity,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: BarsPainter(
                        sim: sim, palette: _palette, repaint: _tick),
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(width: w * 0.05),
      ],
    );
  }

  // ------------------------------------------------------------------- pieces

  String get _titleStr => model.active && model.title.isNotEmpty
      ? model.title
      : 'Nothing playing';

  String get _artistStr => model.active
      ? model.artist
      : 'Start music in any player app';

  Text _titleText(double size) => Text(
        _titleStr,
        maxLines: 1,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w300,
          color: Colors.white,
          height: 1.1,
        ),
      );

  Text _artistText(double size) => Text(
        _artistStr.toUpperCase(),
        maxLines: 1,
        style: TextStyle(
          fontSize: size,
          fontWeight: FontWeight.w400,
          letterSpacing: size * 0.38,
          color: Colors.white.withOpacity(0.62),
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

  Widget _fit(Widget child, Alignment align) => FittedBox(
        fit: BoxFit.scaleDown,
        alignment: align,
        child: child,
      );

  Widget _artCard(double s) {
    final p = _palette;
    final radius = s * 0.07;
    final art = model.art;
    return RepaintBoundary(
      child: Container(
        width: s,
        height: s,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
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
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 500),
            child: art == null
                ? Container(
                    key: const ValueKey('placeholder'),
                    color: const Color(0xFF111827),
                    child: Icon(Icons.music_note,
                        size: s * 0.35, color: Colors.white24),
                  )
                : Image.memory(
                    art.bytes,
                    key: ValueKey(art),
                    width: s,
                    height: s,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.high,
                  ),
          ),
        ),
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
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xCC000000),
            borderRadius: BorderRadius.circular(60),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              btn(Icons.view_carousel_outlined, 36, _toggleTheme),
              const SizedBox(width: 12),
              btn(Icons.skip_previous_rounded, 56, model.previous),
              btn(model.playing ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  76, model.playPause),
              btn(Icons.skip_next_rounded, 56, model.next),
              const SizedBox(width: 16),
              AnimatedBuilder(
                animation: _tick,
                builder: (context, _) => Text(
                  '${_fmt(model.positionMs)} / ${_fmt(model.durationMs)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
              ),
              const SizedBox(width: 8),
            ],
          ),
        ),
      ),
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
