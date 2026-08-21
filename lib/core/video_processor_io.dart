// モバイル（Android/iOS）向け動画パススルー。
// ffmpeg-kit の Maven 依存が廃止のため、カメラ出力をそのままバイト列として返す。
// ステッカーの焼き付けは行わない（表示オーバーレイのみ）。

import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../models/sticker_overlay.dart';
import '../models/video_filter.dart';

Future<ProcessedVideo> processVideo(
  XFile input, {
  List<StickerOverlay> stickers = const [],
  bool needsFlip = false,
  VideoFilter filter = VideoFilter.none,
}) async {
  debugPrint('[video-io] 処理開始 filter=${filter.name}: ${input.path}');
  final file = File(input.path);
  if (filter != VideoFilter.none) {
    final outputPath =
        '${Directory.systemTemp.path}/hanalog_${DateTime.now().microsecondsSinceEpoch}.mp4';
    final command = [
      '-y',
      '-i',
      input.path,
      '-vf',
      filter.ffmpegExpression,
      '-c:v',
      'libx264',
      '-preset',
      'ultrafast',
      '-crf',
      '28',
      '-c:a',
      'aac',
      '-movflags',
      '+faststart',
      outputPath,
    ];
    final session = await FFmpegKit.executeWithArguments(command);
    final returnCode = await session.getReturnCode();
    if (ReturnCode.isSuccess(returnCode)) {
      final output = File(outputPath);
      final bytes = await output.readAsBytes();
      await output.delete();
      debugPrint('[video-io] ✅ フィルター焼き付け完了: ${bytes.length} bytes');
      return ProcessedVideo(
        bytes: bytes,
        extension: 'mp4',
        mimeType: 'video/mp4',
      );
    }
    debugPrint('[video-io] ⚠️ FFmpeg失敗。元動画をそのまま使用します: $returnCode');
    try {
      await File(outputPath).delete();
    } catch (_) {}
  }
  final bytes = await file.readAsBytes();
  debugPrint('[video-io] ✅ 読み込み完了: ${bytes.length} bytes');
  return ProcessedVideo(bytes: bytes, extension: 'mp4', mimeType: 'video/mp4');
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
