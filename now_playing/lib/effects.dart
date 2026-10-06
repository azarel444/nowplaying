import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'palette.dart';

double _a(double v) => v.clamp(0.0, 1.0).toDouble();

// ------------------------------------------------------------- particles

/// Slowly rising embers. Position is a pure function of [t], so nothing is
/// allocated per frame.
class ParticleField {
  static const int n = 36;
  final List<double> x = [];
  final List<double> y = [];
  final List<double> r = [];
  final List<double> s = [];
  final List<double> ph = [];
  double t = 0;

  ParticleField() {
    final rnd = math.Random(5);
    for (int i = 0; i < n; i++) {
      x.add(rnd.nextDouble());
      y.add(rnd.nextDouble());
      r.add(1.5 + rnd.nextDouble() * 3.0);
      s.add(0.05 + rnd.nextDouble() * 0.10);
      ph.add(rnd.nextDouble() * 6.283);
    }
  }
}

class ParticlesPainter extends CustomPainter {
  final ParticleField field;
  final ArtPalette palette;

  ParticlesPainter({
    required this.field,
    required this.palette,
    required Listenable repaint,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint();
    final t = field.t;
    for (int i = 0; i < ParticleField.n; i++) {
      final yy = (field.y[i] - t * field.s[i]) % 1.0;
      final xx =
          (field.x[i] + 0.015 * math.sin(t * 1.3 + field.ph[i])) * size.width;
      final py = yy * size.height;
      final edge = math.sin(yy * math.pi);
      final tw = 0.5 + 0.5 * math.sin(t * 2.0 + field.ph[i] * 3.0);
      final alpha = _a((0.25 + 0.30 * tw) * edge);
      final c = palette.at(field.x[i]);
      p.color = c.withOpacity(alpha * 0.25);
      canvas.drawCircle(Offset(xx, py), field.r[i] * 3.2, p);
      p.color = c.withOpacity(alpha);
      canvas.drawCircle(Offset(xx, py), field.r[i], p);
    }
  }

  @override
  bool shouldRepaint(ParticlesPainter old) => old.palette != palette;
}

// ------------------------------------------------------------------- VHS

/// Faint horizontal lines. Drawn once and cached (no repaint listener).
class ScanlinePainter extends CustomPainter {
  final double alpha;
  ScanlinePainter({required this.alpha});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Color.fromRGBO(0, 0, 0, _a(alpha))
      ..strokeWidth = 1.2;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(ScanlinePainter old) => old.alpha != alpha;
}

/// A small tile of random noise, made once and then just moved around.
Future<ui.Image> makeNoiseImage() {
  const size = 128;
  final r = math.Random(7);
  final px = Uint8List(size * size * 4);
  for (int i = 0; i < size * size; i++) {
    final a = 40 + r.nextInt(70);
    final v = (r.nextInt(256) * a) ~/ 255; // premultiplied gray
    px[i * 4] = v;
    px[i * 4 + 1] = v;
    px[i * 4 + 2] = v;
    px[i * 4 + 3] = a;
  }
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(px, size, size, ui.PixelFormat.rgba8888, c.complete);
  return c.future;
}

/// Film grain: the noise tile jumps to a new offset about 10 times a second.
class GrainPainter extends CustomPainter {
  final ui.Image? noise;
  final double k;
  final ValueListenable<int> tick;

  GrainPainter({required this.noise, required this.k, required this.tick})
      : super(repaint: tick);

  @override
  void paint(Canvas canvas, Size size) {
    final img = noise;
    if (img == null) return;
    final n = tick.value;
    final dx = ((n * 53) % 128).toDouble();
    final dy = ((n * 97) % 128).toDouble();
    final p = Paint()
      ..shader = ui.ImageShader(img, TileMode.repeated, TileMode.repeated,
          Matrix4.translationValues(dx, dy, 0).storage)
      ..color = Color.fromRGBO(255, 255, 255, _a(k));
    canvas.drawRect(Offset.zero & size, p);
  }

  @override
  bool shouldRepaint(GrainPainter old) => old.noise != noise || old.k != k;
}

/// Shared state for the tracking-glitch bands. The screen updates it;
/// the painter only reads it.
class GlitchState {
  double active = 0; // 0..1, fades in and out
  double y = 0.5; // 0..1 vertical position of the first band
  int bands = 1;
  int seed = 1;
}

class GlitchPainter extends CustomPainter {
  final GlitchState g;
  final double k;

  GlitchPainter({required this.g, required this.k, required Listenable repaint})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final a = g.active * k;
    if (a <= 0.01) return;
    final r = math.Random(g.seed);
    final p = Paint();
    for (int b = 0; b < g.bands; b++) {
      final y = ((g.y + b * 0.23 + r.nextDouble() * 0.05) % 1.0) * size.height;
      final bh = size.height * (0.012 + r.nextDouble() * 0.03);
      final shift = (r.nextDouble() - 0.5) * size.width * 0.05;

      p.color = Color.fromRGBO(255, 255, 255, _a(0.10 * a));
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, bh), p);
      p.color = Color.fromRGBO(255, 46, 147, _a(0.22 * a));
      canvas.drawRect(Rect.fromLTWH(shift, y, size.width, bh * 0.35), p);
      p.color = Color.fromRGBO(5, 217, 255, _a(0.22 * a));
      canvas.drawRect(
          Rect.fromLTWH(-shift, y + bh * 0.65, size.width, bh * 0.35), p);

      p.color = Color.fromRGBO(255, 255, 255, _a(0.35 * a));
      for (int i = 0; i < 14; i++) {
        final x = r.nextDouble() * size.width;
        final w = size.width * (0.02 + r.nextDouble() * 0.08);
        canvas.drawRect(
            Rect.fromLTWH(x, y + r.nextDouble() * bh, w, 1.5), p);
      }
    }
  }

  @override
  bool shouldRepaint(GlitchPainter old) => old.k != k;
}

// ------------------------------------------------------------ vaporwave

const double _horizon = 0.66;

/// Retro striped sun sitting on the horizon. Static, so it is cached.
class SunPainter extends CustomPainter {
  final double k;
  SunPainter({required this.k});

  @override
  void paint(Canvas canvas, Size size) {
    final hy = size.height * _horizon;
    final r = math.min(size.width, size.height) * 0.26;
    final c = Offset(size.width * 0.5, hy - r * 0.45);
    final rect = Rect.fromCircle(center: c, radius: r);

    canvas.saveLayer(Rect.fromLTWH(0, 0, size.width, hy), Paint());
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, hy));
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromRGBO(255, 224, 102, _a(0.55 * k)),
            Color.fromRGBO(255, 46, 147, _a(0.55 * k)),
          ],
        ).createShader(rect),
    );
    final clear = Paint()..blendMode = BlendMode.clear;
    for (int i = 0; i < 6; i++) {
      final yy = c.dy + r * (0.05 + i * 0.16);
      final hh = r * (0.02 + 0.016 * i);
      canvas.drawRect(Rect.fromLTWH(c.dx - r, yy, 2 * r, hh), clear);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(SunPainter old) => old.k != k;
}

class GridState {
  double scroll = 0;
}

/// Perspective grid floor that scrolls toward the viewer.
class GridPainter extends CustomPainter {
  final GridState state;
  final double k;

  GridPainter({required this.state, required this.k, required Listenable repaint})
      : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    final hy = size.height * _horizon;
    final cx = size.width / 2;

    canvas.drawRect(
      Rect.fromLTWH(0, hy, size.width, size.height - hy),
      Paint()..color = Color.fromRGBO(20, 0, 40, _a(0.35 * k)),
    );

    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    p.color = Color.fromRGBO(255, 46, 147, _a(0.5 * k));
    canvas.drawLine(Offset(0, hy), Offset(size.width, hy), p);

    const n = 9;
    for (int i = 0; i < n; i++) {
      final z = ((i + state.scroll) % n) / n;
      final y = hy + (size.height - hy) * z * z;
      p.color = Color.fromRGBO(185, 103, 255, _a((0.15 + 0.55 * z) * k));
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }

    p.color = Color.fromRGBO(5, 217, 255, _a(0.30 * k));
    for (int j = -8; j <= 8; j++) {
      canvas.drawLine(
        Offset(cx + j * size.width * 0.012, hy),
        Offset(cx + j * size.width * 0.11, size.height),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(GridPainter old) => old.k != k;
}
