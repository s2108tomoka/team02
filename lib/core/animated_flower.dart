// 未投稿状態で表示するハイビスカスのアニメーション。
// 投稿がない画面にも動きを加え、次の投稿を待つ時間を楽しく見せる。

import 'dart:math' as math;

import 'package:flutter/material.dart';

class AnimatedFlower extends StatefulWidget {
  const AnimatedFlower({
    super.key,
    this.size = 96,
    this.width,
    this.height,
    this.phase = 0,
  });

  final double size;
  final double? width;
  final double? height;
  final double phase;

  @override
  State<AnimatedFlower> createState() => _AnimatedFlowerState();
}

class _AnimatedFlowerState extends State<AnimatedFlower>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '投稿を待っている花',
      image: true,
      child: SizedBox(
        width: widget.width ?? widget.size + 16,
        height: widget.height ?? widget.size + 16,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final maxX = math.max(0, (constraints.maxWidth - widget.size) / 2);
            final maxY = math.max(0, (constraints.maxHeight - widget.size) / 2);

            return AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final value = (_controller.value + widget.phase) % 1.0;
                // XとYの周期を少しずらし、矩形の中をゆっくり跳ね返るように見せる。
                final x = math.sin(value * math.pi * 2) * maxX;
                final y = math.sin(value * math.pi * 1.4 + 1.2) * maxY;
                return Transform.translate(
                  offset: Offset(x, y),
                  child: Transform.rotate(
                    angle: (x / math.max(maxX, 1)) * .08,
                    child: child,
                  ),
                );
              },
              child: Image.asset(
                'assets/images/hanalog_hibiscus_icon.png',
                width: widget.size,
                height: widget.size,
                fit: BoxFit.contain,
              ),
            );
          },
        ),
      ),
    );
  }
}
