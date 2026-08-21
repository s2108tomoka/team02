import 'package:flutter/material.dart';

import '../models/video_filter.dart';

/// カメラ・送信プレビューに撮影時の色味を表示する軽量なオーバーレイ。
Widget withVideoFilter(Widget child, VideoFilter filter) {
  if (filter == VideoFilter.none) return child;
  return Stack(
    fit: StackFit.expand,
    children: [
      child,
      IgnorePointer(
        child: ColoredBox(
          color: filter.previewColor.withAlpha(
            (filter.previewOpacity * 255).round(),
          ),
        ),
      ),
    ],
  );
}
