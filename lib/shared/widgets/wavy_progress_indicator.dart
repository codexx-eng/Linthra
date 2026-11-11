import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class WavyProgressIndicator extends StatefulWidget {
  const WavyProgressIndicator({
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    this.thumbColor,
    this.amplitude = 3.0,
    this.wavelength = 20.0,
    this.strokeWidth = 3.0,
    this.thumbRadius = 0.0,
    this.active = true,
    this.transitionDuration = const Duration(milliseconds: 420),
    super.key,
  })  : assert(amplitude >= 0, 'amplitude must not be negative'),
        assert(wavelength > 0, 'wavelength must be positive'),
        assert(strokeWidth > 0, 'strokeWidth must be positive'),
        assert(thumbRadius >= 0, 'thumbRadius must not be negative');

  final double value;
  final Color activeColor;
  final Color inactiveColor;
  final Color? thumbColor;
  final double amplitude;
  final double wavelength;
  final double strokeWidth;
  final double thumbRadius;
  final bool active;
  final Duration transitionDuration;

  static double trackInset({
    required double thumbRadius,
    required double strokeWidth,
  }) =>
      math.max(thumbRadius, strokeWidth / 2);

  @override
  State<WavyProgressIndicator> createState() => _WavyProgressIndicatorState();
}

class _WavyProgressIndicatorState extends State<WavyProgressIndicator> {
  static const MethodChannel _channel =
      MethodChannel('io.github.thezupzup.linthra/cava_visualizer');

  Timer? _timer;
  List<double> _bands = List<double>.filled(32, 0.0);
  double _fallbackPhase = 0.0;

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      _startAudioSync();
    }
  }

  @override
  void didUpdateWidget(WavyProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) {
      if (widget.active) {
        _startAudioSync();
      } else {
        _stopAudioSync();
      }
    }
  }

  Future<void> _startAudioSync() async {
    _timer?.cancel();
    try {
      await _channel.invokeMethod('start');
    } catch (_) {}

    _timer = Timer.periodic(const Duration(milliseconds: 35), (_) async {
      if (!mounted || !widget.active) return;
      _fallbackPhase += 0.18;
      try {
        final List<dynamic>? raw =
            await _channel.invokeMethod<List<dynamic>>('getBands');
        if (!mounted) return;
        if (raw != null && raw.length == 32) {
          double sum = 0;
          final next = List<double>.filled(32, 0.0);
          for (int i = 0; i < 32; i++) {
            final v = ((raw.elementAt(i) as num).toDouble() * 1.45).clamp(0.0, 1.0);
            sum += v;
            final prev = _bands.elementAt(i);
            next.insert(i, v > prev ? v : (prev * 0.68 + v * 0.32));
          }
          setState(() {
            _bands = sum > 0.01 ? next.sublist(0, 32) : _simulatedBands(_fallbackPhase);
          });
          return;
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _bands = _simulatedBands(_fallbackPhase);
        });
      }
    });
  }

  void _stopAudioSync() {
    _timer?.cancel();
    _timer = null;
    try {
      _channel.invokeMethod('stop');
    } catch (_) {}
    if (mounted) {
      setState(() {
        _bands = List<double>.filled(32, 0.0);
      });
    }
  }

  List<double> _simulatedBands(double t) {
    final beat = math.pow((math.sin(t * 2.0) + 1.0) / 2.0, 1.5).toDouble();
    return List<double>.generate(32, (i) {
      final w1 = math.sin(i * 0.95 + t * 2.5);
      final w2 = math.cos(i * 1.85 - t * 3.5);
      final raw = ((w1 * 0.55 + w2 * 0.45) + 1.0) / 2.0;
      return (raw * (0.4 + 0.6 * beat)).clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    try {
      _channel.invokeMethod('stop');
    } catch (_) {}
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _WavyProgressPainter(
          bands: _bands,
          value: widget.value,
          activeColor: widget.activeColor,
          inactiveColor: widget.inactiveColor,
          amplitude: widget.amplitude,
          strokeWidth: widget.strokeWidth,
          thumbRadius: widget.thumbRadius,
          textDirection: Directionality.of(context),
        ),
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  _WavyProgressPainter({
    required this.bands,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.amplitude,
    required this.strokeWidth,
    required this.thumbRadius,
    required this.textDirection,
  });

  final List<double> bands;
  final double value;
  final Color activeColor;
  final Color inactiveColor;
  final double amplitude;
  final double strokeWidth;
  final double thumbRadius;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final double inset = WavyProgressIndicator.trackInset(
      thumbRadius: thumbRadius,
      strokeWidth: strokeWidth,
    );
    final double trackWidth = size.width - inset * 2;
    if (trackWidth <= 0) return;

    final double fraction = _safeFraction(value);
    final double elapsed = trackWidth * fraction;

    final bool rtl = textDirection == TextDirection.rtl;
    final double origin = rtl ? size.width - inset : inset;
    final double direction = rtl ? -1.0 : 1.0;

    final double baseY = (size.height / 2) + math.max(14.0, amplitude * 4.5);
    final double maxBarHeight = math.max(30.0, amplitude * 11.0);
    final double minBarHeight = 2.5;

    final double barWidth = math.max(3.2, strokeWidth * 1.15);
    final double gap = 2.2;
    final double step = barWidth + gap;
    final int barCount = math.max(1, (trackWidth / step).floor());

    final Paint barPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    const Radius barRadius = Radius.circular(1.0);

    for (int i = 0; i < barCount; i++) {
      final double normPos = barCount > 1 ? i / (barCount - 1) : 0.0;
      final double d = (i + 0.5) * (trackWidth / barCount);
      final double x = origin + direction * d;
      final bool isElapsed = d <= elapsed;

      // Estilo Cava real: graves na esquerda (0) ate agudos na direita (31)
      final int bandIdx =
          (normPos * (bands.length - 1)).round().clamp(0, bands.length - 1);
      final double energy = bands.elementAt(bandIdx);

      final double barHeight =
          minBarHeight + (maxBarHeight - minBarHeight) * energy;

      barPaint.color = isElapsed ? activeColor : inactiveColor;

      final Rect rect = Rect.fromLTWH(
        x - barWidth / 2,
        baseY - barHeight,
        barWidth,
        barHeight,
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, barRadius), barPaint);
    }
  }

  static double _safeFraction(double value) {
    if (!value.isFinite) return 0;
    return value.clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_WavyProgressPainter oldDelegate) => true;
}
