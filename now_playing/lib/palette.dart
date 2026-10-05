import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Three accent colors pulled from the album art. Used for the glow,
/// the visualizer gradient and the progress line.
class ArtPalette {
  final Color a, b, c;
  const ArtPalette(this.a, this.b, this.c);

  static const fallback = ArtPalette(
    Color(0xFF00E5FF), // cyan
    Color(0xFFD65CFF), // magenta
    Color(0xFFFF9A5A), // orange
  );

  List<Color> get colors => [a, b, c];

  /// t: 0 (left) .. 1 (right)
  Color at(double t) {
    t = t.clamp(0.0, 1.0).toDouble();
    return t < 0.5
        ? Color.lerp(a, b, t * 2)!
        : Color.lerp(b, c, (t - 0.5) * 2)!;
  }
}

/// Decoded album art: the original bytes for the sharp card, plus a tiny
/// decoded copy that is scaled up for the soft background (cheap "blur"
/// that costs nothing per frame on slow head units).
class ArtAssets {
  final Uint8List bytes;
  final ui.Image tiny;
  final ArtPalette palette;
  ArtAssets(this.bytes, this.tiny, this.palette);

  static Future<ArtAssets?> load(Uint8List bytes) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes, targetWidth: 96);
      final frame = await codec.getNextFrame();
      final img = frame.image;
      final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
      final palette = data == null
          ? ArtPalette.fallback
          : _extract(data, img.width, img.height);
      return ArtAssets(bytes, img, palette);
    } catch (_) {
      return null;
    }
  }

  static ArtPalette _extract(ByteData d, int w, int h) {
    final cands = <_Cand>[];
    for (int i = 0; i < w * h; i++) {
      final r = d.getUint8(i * 4);
      final g = d.getUint8(i * 4 + 1);
      final b = d.getUint8(i * 4 + 2);
      final hsv = HSVColor.fromColor(Color.fromARGB(255, r, g, b));
      if (hsv.saturation < 0.25 || hsv.value < 0.25) continue;
      cands.add(_Cand(hsv, hsv.saturation * hsv.value));
    }
    if (cands.isEmpty) return ArtPalette.fallback;
    cands.sort((x, y) => y.score.compareTo(x.score));

    final first = cands.first.hsv;
    HSVColor? second;
    for (final c in cands) {
      if (_hueDist(c.hsv.hue, first.hue) >= 50) {
        second = c.hsv;
        break;
      }
    }
    second ??= first.withHue((first.hue + 70) % 360);

    HSVColor? third;
    for (final c in cands) {
      if (_hueDist(c.hsv.hue, first.hue) >= 40 &&
          _hueDist(c.hsv.hue, second.hue) >= 40) {
        third = c.hsv;
        break;
      }
    }
    third ??= second.withHue((second.hue + 50) % 360);

    return ArtPalette(_vivid(first), _vivid(second), _vivid(third));
  }

  static double _hueDist(double a, double b) {
    final d = (a - b).abs() % 360;
    return d > 180 ? 360 - d : d;
  }

  static Color _vivid(HSVColor c) => c
      .withSaturation(math.max(c.saturation, 0.6))
      .withValue(math.max(c.value, 0.85))
      .toColor();
}

class _Cand {
  final HSVColor hsv;
  final double score;
  _Cand(this.hsv, this.score);
}
