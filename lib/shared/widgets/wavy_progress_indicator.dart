import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

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

class _WavyProgressIndicatorState extends State<WavyProgressIndicator>
    with TickerProviderStateMixin {
  static const double _restingScale = 0.12;

  late final AnimationController _swellController = AnimationController(
    vsync: this,
    duration: widget.transitionDuration,
    value: widget.active ? 1.0 : 0.0,
  );

  late final Animation<double> _swell = _swellController.drive(
    Tween<double>(begin: _restingScale, end: 1.0)
        .chain(CurveTween(curve: Curves.easeOutCubic)),
  );

  late final AnimationController _cavaController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) {
      unawaited(_cavaController.repeat());
    }
  }

  @override
  void didUpdateWidget(WavyProgressIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.transitionDuration != widget.transitionDuration) {
      _swellController.duration = widget.transitionDuration;
    }
    if (widget.active) {
      if (!_cavaController.isAnimating) {
        unawaited(_cavaController.repeat());
      }
      if (_swellController.value < 1.0 && !_swellController.isAnimating) {
        unawaited(_swellController.forward());
      }
    } else {
      if (_cavaController.isAnimating) {
        _cavaController.stop();
      }
      if (_swellController.value > 0.0 && !_swellController.isAnimating) {
        unawaited(_swellController.reverse());
      }
    }
  }

  @override
  void dispose() {
    _swellController.dispose();
    _cavaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([_swell, _cavaController]),
        builder: (BuildContext context, Widget? child) {
          return CustomPaint(
            size: Size.infinite,
            painter: _WavyProgressPainter(
              swellValue: _swell.value,
              phaseValue: _cavaController.value,
              value: widget.value,
              activeColor: widget.activeColor,
              inactiveColor: widget.inactiveColor,
              thumbColor: widget.thumbColor ?? widget.activeColor,
              amplitude: widget.amplitude,
              wavelength: widget.wavelength,
              strokeWidth: widget.strokeWidth,
              thumbRadius: widget.thumbRadius,
              textDirection: Directionality.of(context),
            ),
          );
        },
      ),
    );
  }
}

class _WavyProgressPainter extends CustomPainter {
  _WavyProgressPainter({
    required this.swellValue,
    required this.phaseValue,
    required this.value,
    required this.activeColor,
    required this.inactiveColor,
    required this.thumbColor,
    required this.amplitude,
    required this.wavelength,
    required this.strokeWidth,
    required this.thumbRadius,
    required this.textDirection,
  });

  final double swellValue;
  final double phaseValue;
  final double value;
  final Color activeColor;
  final Color inactiveColor;
  final Color thumbColor;
  final double amplitude;
  final double wavelength;
  final double strokeWidth;
  final double thumbRadius;
  final TextDirection textDirection;

  static const double _haloScale = 1.7;
  static const double _haloAlpha = 0.22;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final double inset = WavyProgressIndicator.trackInset(
      thumbRadius: thumbRadius,
      strokeWidth: strokeWidth,
    );
    final double trackWidth = size.width - inset * 2;
    if (trackWidth <= 0) return;

    final double centerY = size.height / 2;
    final double fraction = _safeFraction(value);
    final double elapsed = trackWidth * fraction;

    final bool rtl = textDirection == TextDirection.rtl;
    final double origin = rtl ? size.width - inset : inset;
    final double direction = rtl ? -1.0 : 1.0;
    final double markerX = origin + direction * elapsed;

    final double barWidth = math.max(2.0, strokeWidth * 0.85);
    final double gap = barWidth * 1.15;
    final double step = barWidth + gap;
    final int barCount = math.max(1, (trackWidth / step).floor());

    final double maxHalfHeight = math.max(5.5, amplitude * 2.8);
    final double minHalfHeight = math.max(1.2, strokeWidth * 0.45);
    final double t = phaseValue * 2 * math.pi;

    final Paint barPaint = Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final Radius barRadius = Radius.circular(barWidth / 2);

    for (int i = 0; i < barCount; i++) {
      final double d = (i + 0.5) * (trackWidth / barCount);
      final double x = origin + direction * d;
      final bool isElapsed = d <= elapsed;

      // Simulacao de espectro de graves, medios e agudos estilo Cava
      final double beat = (math.sin(t * 2.0) + 1.0) / 2.0;
      final double w1 = math.sin(i * 0.85 + t * 3.0);
      final double w2 = math.cos(i * 1.65 - t * 4.0);
      final double w3 = math.sin(i * 2.40 + t * 2.0);
      final double raw = ((w1 * 0.45 + w2 * 0.35 + w3 * 0.20) + 1.0) / 2.0;
      final double energy = (raw * (0.55 + 0.45 * beat)).clamp(0.0, 1.0);

      final double regionScale = isElapsed ? 1.0 : 0.40;
      final double dynamicJump =
          (maxHalfHeight - minHalfHeight) * energy * swellValue * regionScale;
      final double halfHeight = minHalfHeight + dynamicJump;

      barPaint.color = isElapsed ? activeColor : inactiveColor;

      final RRect rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(x, centerY),
          width: barWidth,
          height: halfHeight * 2,
        ),
        barRadius,
      );
      canvas.drawRRect(rrect, barPaint);
    }

    if (thumbRadius > 0) {
      final Paint fill = Paint()..isAntiAlias = true;
      canvas.drawCircle(
        Offset(markerX, centerY),
        thumbRadius * _haloScale,
        fill..color = thumbColor.withValues(alpha: _haloAlpha),
      );
      canvas.drawCircle(
        Offset(markerX, centerY),
        thumbRadius,
        fill..color = thumbColor,
      );
    }
  }

  static double _safeFraction(double value) {
    if (!value.isFinite) return 0;
    return value.clamp(0.0, 1.0);
  }

  @override
  bool shouldRepaint(_WavyProgressPainter oldDelegate) =>
      oldDelegate.value != value ||
      oldDelegate.activeColor != activeColor ||
      oldDelegate.inactiveColor != inactiveColor ||
      oldDelegate.thumbColor != thumbColor ||
      oldDelegate.amplitude != amplitude ||
      oldDelegate.wavelength != wavelength ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.thumbRadius != thumbRadius ||
      oldDelegate.textDirection != textDirection ||
      oldDelegate.swellValue != swellValue ||
      oldDelegate.phaseValue != phaseValue;
}
