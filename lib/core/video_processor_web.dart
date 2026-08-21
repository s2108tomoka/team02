// Web向け動画変換。ffmpeg.wasmで720p縦型mp4に統一し、ステッカーを焼き付ける。
// ステッカーのPNGレンダリングはJS側(web/ffmpeg_helper.js)のCanvasで行う。
// 座標変換(表示空間→ファイル空間)はDart側で計算してJSに渡す。

import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:camera/camera.dart';

import '../models/sticker_overlay.dart';
import '../models/video_filter.dart';

@JS('processVideoWeb')
external JSPromise<JSUint8Array> _processVideoWeb(
  JSUint8Array input,
  JSString stickersJson,
  JSString filterName,
);

Future<ProcessedVideo> processVideo(
  XFile input, {
  List<StickerOverlay> stickers = const [],
  bool needsFlip = false,
  VideoFilter filter = VideoFilter.none,
}) async {
  final inputBytes = await input.readAsBytes();

  // ステッカーの座標を表示空間(16:9)からファイル空間(720x1280)に変換する。
  // Web: 90°CW + 水平反転で表示 → col = display_y*720, row = display_x*1280
  // Web(needsFlip): 270°CW + 水平反転 → col = (1-display_y)*720, row = (1-display_x)*1280
  final stickerData = stickers.map((s) {
    final col = needsFlip
        ? ((1 - s.y) * 720 - 40).round().clamp(0, 640)
        : (s.y * 720 - 40).round().clamp(0, 640);
    final row = needsFlip
        ? ((1 - s.x) * 1280 - 40).round().clamp(0, 1200)
        : (s.x * 1280 - 40).round().clamp(0, 1200);
    return {'emoji': s.emoji, 'col': col, 'row': row};
  }).toList();

  final stickersJson = jsonEncode(stickerData);

  // ignore: avoid_print
  print(
    '[ffmpeg-web/dart] 変換要求: 入力 ${inputBytes.length} bytes, '
    'ステッカー ${stickers.length} 件',
  );
  try {
    final result = await _processVideoWeb(
      inputBytes.toJS,
      stickersJson.toJS,
      filter.name.toJS,
    ).toDart;
    final bytes = result.toDart;
    // ignore: avoid_print
    print('[ffmpeg-web/dart] 変換成功: 出力 ${bytes.length} bytes');
    return ProcessedVideo(
      bytes: bytes,
      extension: 'mp4',
      mimeType: 'video/mp4',
    );
  } catch (e) {
    // ignore: avoid_print
    print('[ffmpeg-web/dart] 変換失敗: $e');
    rethrow;
  }
}

class ProcessedVideo {
  const ProcessedVideo({
    required this.bytes,
    required this.extension,
    required this.mimeType,
  });

  final Uint8List bytes;
  final String extension;
  final String mimeType;
}
