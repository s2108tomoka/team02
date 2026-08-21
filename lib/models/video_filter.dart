import 'package:flutter/material.dart';

/// 撮影・送信プレビューと動画変換で共有するフィルター設定。
enum VideoFilter { none, warm, blue, pink }

extension VideoFilterDetails on VideoFilter {
  String get label => switch (this) {
    VideoFilter.none => 'なし',
    VideoFilter.warm => '暖色',
    VideoFilter.blue => 'ブルー',
    VideoFilter.pink => 'ピンク',
  };

  Color get previewColor => switch (this) {
    VideoFilter.none => Colors.transparent,
    VideoFilter.warm => const Color(0xFFFF8A3D),
    VideoFilter.blue => const Color(0xFF4D9DE0),
    VideoFilter.pink => const Color(0xFFFF4F9A),
  };

  double get previewOpacity => this == VideoFilter.none ? 0 : 0.2;

  /// FFmpegの colorchannelmixer 用の係数。
  String get ffmpegExpression => switch (this) {
    VideoFilter.none => '',
    VideoFilter.warm => 'colorchannelmixer=rr=1.08:gg=1.02:bb=0.90',
    VideoFilter.blue => 'colorchannelmixer=rr=0.88:gg=1.02:bb=1.16',
    VideoFilter.pink => 'colorchannelmixer=rr=1.12:gg=0.90:bb=1.04',
  };
}
