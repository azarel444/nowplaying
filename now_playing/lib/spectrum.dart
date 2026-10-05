import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'palette.dart';

/// Simulated spectrum. Looks like music, follows play/pause, but is not
/// tied to the actual audio signal.
class SpectrumSim {
  static const int bars = 96;

  final List<double> levels = List<double>.filled(bars, 0.03);
  final List<double> _phase;
  final List<double> _freq;
  double _t = 0;
  double _energy = 0;

  SpectrumSim()
      : _phase = _rand(bars, 6.283, 0, 11),
        _freq = _rand(bars, 5.0, 1.5, 23);

  static List<double> _rand(int n, double scale, double offset, int seed) {
    final r = math.Random(seed);
    return List<double>.generate(n, (_) => offset + r.nextDouble() * scale);
  }

  static double _envelope(double x) {
    final d = (x - 0.3) / 0.28;
    return 0.35 + 0.65 * math.exp(-d * d);
  }

  /// [real]: optional frequency bands (0..255 each, [bars] long) from the
  /// device's audio output. When given, the bars follow it; otherwise the
  /// simulation runs.
  void update(double dt, bool playing, {Uint8List? real}) {
    _t += dt;

    if (real != null && real.length >= bars) {
      _energy = 1.0;
      for (int i = 0; i < bars; i++) {
        final v = math.pow(real[i] / 255.0, 0.9).toDouble();
        final target = 0.03 + 0.97 * v;
        final rate = target > levels[i] ? 24.0 : 10.0;
        levels[i] += (target - levels[i]) * math.min(1.0, dt * rate);
      }
      return;
    }

    _energy += ((playing ? 1.0 : 0.0) - _energy) * math.min(1.0, dt * 3.0);

    final beatPhase = (_t * 2.0) % 1.0; // ~120 bpm
    final beat =
        math.pow(math.max(0.0, 1.0 - beatPhase * 3.0), 2.0).toDouble();
    final swell = 0.5 + 0.5 * math.sin(_t * 0.45);

    for (int i = 0; i < bars; i++) {
      final x = i / (bars - 1);
      final env = _envelope(x);
      final wob = 0.5 + 0.5 * math.sin(_t * _freq[i] + _phase[i]);
      final bass = math.max(0.0, 1.0 - x * 3.0);

      var target = env * (0.22 + 0.5 * wob + 0.28 * swell * wob) +
          0.45 * beat * bass * env +
          0.15 * beat * (1 - bass) * wob * env;
      target = target.clamp(0.0, 1.0).toDouble();
      target = 0.03 + _energy * target * 0.97;

      final rate = target > levels[i] ? 16.0 : 6.0;
      levels[i] += (target - levels[i]) * math.min(1.0, dt * rate);
    }
  }
}

/// Circular ring of bars that wraps around the album art. Open at the
/// bottom so the title can sit underneath.
class RingPainter extends CustomPainter {
  final SpectrumSim sim;
  final ArtPalette palette;
  final double innerRadius;
  final double maxLen;

  RingPainter({
    required this.sim,
    required this.palette,
    required this.innerRadius,
    required this.maxLen,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    const count = SpectrumSim.bars;
    const gap = 0.30;
    const start = math.pi / 2 + gap;
    const sweep = 2 * math.pi - 2 * gap;
    final width = innerRadius * 0.045;

    final glow = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = width * 2.4;
    final bar = Paint()
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    for (int i = 0; i < count; i++) {
      final f = i / (count - 1);
      final ang = start + sweep * f;
      final u = (f - 0.5).abs() * 2; // 0 at top, 1 at the bottom ends
      final level = sim.levels[(u * (count - 1)).round()];
      final len = width + maxLen * level;

      final dir = Offset(math.cos(ang), math.sin(ang));
      final p1 = c + dir * innerRadius;
      final p2 = c + dir * (innerRadius + len);
      final color = palette.at((1 + math.cos(ang)) / 2);

      glow.color = color.withOpacity(0.16);
      bar.color = color;
      canvas.drawLine(p1, p2, glow);
      canvas.drawLine(p1, p2, bar);
    }
  }

  @override
  bool shouldRepaint(RingPainter old) =>
      old.palette != palette ||
      old.innerRadius != innerRadius ||
      old.maxLen != maxLen;
}

/// Horizontal spectrum with a soft reflection underneath.
class BarsPainter extends CustomPainter {
  final SpectrumSim sim;
  final ArtPalette palette;

  BarsPainter({
    required this.sim,
    required this.palette,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    const n = SpectrumSim.bars;
    final barsH = size.height * 0.72;
    final baseY = barsH;
    final step = size.width / n;
    final bw = step * 0.42;
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);

    final bar = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeWidth = bw
      ..shader = LinearGradient(colors: palette.colors).createShader(rect);
    final refl = Paint()
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = bw
      ..shader = LinearGradient(
        colors: palette.colors.map((c) => c.withOpacity(0.2)).toList(),
      ).createShader(rect);

    for (int i = 0; i < n; i++) {
      final x = step * (i + 0.5);
      final h = math.max(bw, sim.levels[i] * barsH);
      canvas.drawLine(Offset(x, baseY), Offset(x, baseY - h), bar);

      final rh = math.min(h * 0.4, size.height - baseY - 2);
      if (rh > 0) {
        canvas.drawLine(Offset(x, baseY + 4), Offset(x, baseY + 4 + rh), refl);
      }
    }
  }

  @override
  bool shouldRepaint(BarsPainter old) => old.palette != palette;
}
