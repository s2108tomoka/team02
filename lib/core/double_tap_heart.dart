// ダブルタップ時に表示するハート演出。表示のみでデータ保存は行わない。

import 'package:flutter/material.dart';
import 'dart:math' as math;

class HeartBurst extends StatefulWidget {
  const HeartBurst({super.key});

  @override
  State<HeartBurst> createState() => _HeartBurstState();
}

class _HeartBurstState extends State<HeartBurst>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final progress = Curves.easeOut.transform(_controller.value);
        return SizedBox(
          width: 170,
          height: 170,
          child: Stack(
            alignment: Alignment.center,
            clipBehavior: Clip.none,
            children: [
              _HeartParticle(
                progress: Curves.elasticOut.transform(_controller.value),
                angle: 0,
                distance: 0,
                size: 88,
                fadeStart: .55,
              ),
              _HeartParticle(
                progress: progress,
                angle: -math.pi * .72,
                distance: 58,
                size: 34,
              ),
              _HeartParticle(
                progress: progress,
                angle: -math.pi * .22,
                distance: 62,
                size: 28,
              ),
              _HeartParticle(
                progress: progress,
                angle: math.pi * .22,
                distance: 58,
                size: 32,
              ),
              _HeartParticle(
                progress: progress,
                angle: math.pi * .72,
                distance: 54,
                size: 26,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _HeartParticle extends StatelessWidget {
  const _HeartParticle({
    required this.progress,
    required this.angle,
    required this.distance,
    required this.size,
    this.fadeStart = 0,
  });

  final double progress;
  final double angle;
  final double distance;
  final double size;
  final double fadeStart;

  @override
  Widget build(BuildContext context) {
    final fadeProgress = ((progress - fadeStart) / (1 - fadeStart)).clamp(
      0.0,
      1.0,
    );
    final opacity = 1 - fadeProgress;
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: Offset(
          math.cos(angle) * distance * progress,
          math.sin(angle) * distance * progress,
        ),
        child: Transform.scale(
          scale: 1 - (progress * .2),
          child: Icon(
            Icons.favorite,
            size: size,
            color: const Color(0xFFFF4F81),
            shadows: const [
              Shadow(
                color: Color(0x66000000),
                blurRadius: 8,
                offset: Offset(0, 3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
