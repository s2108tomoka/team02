// 投稿（撮影・送信）の状態とロジックを管理するProvider群。
// 撮影した動画の保持・参加中グループ取得・Storageアップロード〜
// posts/post_shares書き込みを担当する。

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/analytics.dart';
import '../../core/app_platform.dart';
import '../../core/jst.dart';
import '../../core/supabase_client.dart';
import '../../core/video_processor.dart';
import '../../models/group.dart';
import '../../models/post.dart';
import '../../models/sticker_overlay.dart';
import '../../models/video_filter.dart';
import '../home/home_provider.dart';

// 撮影直後の動画。ファイルと向き補正フラグ(needsFlip)を送信画面へ受け渡す。
class RecordedVideo {
  const RecordedVideo({
    required this.file,
    this.needsFlip = false,
    this.filter = VideoFilter.none,
  });

  final XFile file;
  // ファイル自体が上下逆に記録された動画(Android前面カメラ等)の補正フラグ。
  final bool needsFlip;
  final VideoFilter filter;
}

// 撮影直後の動画を送信画面へ受け渡すための保持先。
// 取り消し・送信完了時に null に戻す。
class RecordedVideoNotifier extends Notifier<RecordedVideo?> {
  @override
  RecordedVideo? build() => null;

  void set(RecordedVideo? video) => state = video;
  void clear() => state = null;
}

final recordedVideoProvider =
    NotifierProvider<RecordedVideoNotifier, RecordedVideo?>(
      RecordedVideoNotifier.new,
    );

class RetakeCountNotifier extends Notifier<int> {
  @override
  int build() => 0;

  int get count => state;
  void increment() => state++;
  void reset() => state = 0;
}

final retakeCountProvider = NotifierProvider<RetakeCountNotifier, int>(
  RetakeCountNotifier.new,
);

// 送信先選択に必要なデータ（参加中グループ）。
class SendTargets {
  const SendTargets({required this.groups});

  final List<Group> groups;
}

// 送信画面で参加中グループを取得するProvider。
final sendTargetsProvider = FutureProvider.autoDispose<SendTargets>((
  ref,
) async {
  final userId = supabase.auth.currentUser?.id;
  if (userId == null) {
    return const SendTargets(groups: []);
  }

  final memberRows = await supabase
      .from('group_members')
      .select('groups(*)')
      .eq('user_id', userId);

  final groups = <Group>[
    for (final row in memberRows)
      if (row['groups'] != null)
        Group.fromJson(row['groups'] as Map<String, dynamic>),
  ];

  return SendTargets(groups: groups);
});

// 撮影・送信の操作（送信処理）を提供するProvider。
final postControllerProvider = Provider<PostController>((ref) {
  return PostController(ref);
});

// 動画アップロード〜posts/post_shares作成を行う送信処理。
class PostController {
  PostController(this._ref);

  final Ref _ref;

  // 自分の投稿を削除する。postsの外部キー設定により共有先も連動して削除される。
  Future<void> deletePost(Post post) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) throw StateError('ログインが必要です');
    if (post.userId != userId) throw StateError('自分の投稿だけ削除できます');

    debugPrint('[post] 削除開始 postId=${post.id}');
    await supabase
        .from('posts')
        .delete()
        .eq('id', post.id)
        .eq('user_id', userId);

    // DB削除を優先し、Storageの動画は取得できたパスだけ後から削除する。
    // 古いURL形式などでパスを取り出せない場合も、投稿自体は削除できる。
    final storagePath = _storagePathFromPublicUrl(post.videoUrl);
    if (storagePath != null) {
      try {
        await supabase.storage.from('videos').remove([storagePath]);
      } catch (e) {
        debugPrint('[post] ⚠️ 動画ファイル削除失敗（投稿は削除済み）: $e');
      }
    }
    _ref.invalidate(myPostsProvider);
    debugPrint('[post] ✅ 削除完了 postId=${post.id}');
  }

  String? _storagePathFromPublicUrl(String videoUrl) {
    final path = Uri.tryParse(videoUrl)?.path;
    if (path == null) return null;
    const marker = '/storage/v1/object/public/videos/';
    final start = path.indexOf(marker);
    if (start < 0) return null;
    return Uri.decodeComponent(path.substring(start + marker.length));
  }

  // 動画を videos バケットへアップロードし、posts と post_shares を作成する。
  // postsは常に作成され「自分のログ」に表示される。
  // groupIdsを指定するとそのグループにも共有する（複数同時送信に対応）。
  Future<void> send({
    required XFile video,
    required List<String> groupIds,
    bool needsFlip = false,
    List<StickerOverlay> stickers = const [],
    VideoFilter filter = VideoFilter.none,
  }) async {
    debugPrint(
      '[post] send() 開始 '
      'groupIds=${groupIds.length}件 '
      'stickers=${stickers.length}件 '
      'needsFlip=$needsFlip '
      'filter=${filter.name}',
    );

    final userId = supabase.auth.currentUser?.id;
    debugPrint('[post] userId=$userId');
    if (userId == null) {
      debugPrint('[post] ❌ 未ログイン');
      throw StateError('ログインが必要です');
    }

    debugPrint(
      '[post] 動画処理開始 '
      'path=${video.path} mimeType=${video.mimeType}',
    );
    final processed = await processVideo(
      video,
      stickers: stickers,
      needsFlip: needsFlip,
      filter: filter,
    );
    debugPrint(
      '[post] 動画処理完了 '
      '${processed.bytes.length} bytes (${(processed.bytes.length / 1024 / 1024).toStringAsFixed(2)} MB)',
    );

    final now = jstNow();
    final path =
        '$userId/${DateTime.now().millisecondsSinceEpoch}.${processed.extension}';
    debugPrint('[post] Storage アップロード開始 path=$path');

    await supabase.storage
        .from('videos')
        .uploadBinary(
          path,
          processed.bytes,
          fileOptions: FileOptions(contentType: processed.mimeType),
        );
    final videoUrl = supabase.storage.from('videos').getPublicUrl(path);
    debugPrint('[post] ✅ アップロード完了 url=$videoUrl');

    debugPrint('[post] posts テーブルに insert');
    final post = await supabase
        .from('posts')
        .insert({
          'user_id': userId,
          'video_url': videoUrl,
          'needs_flip': needsFlip,
          'platform': currentPlatform,
        })
        .select()
        .single();
    final postId = post['id'] as String;
    debugPrint('[post] ✅ posts insert 完了 postId=$postId');

    if (groupIds.isNotEmpty) {
      debugPrint('[post] post_shares insert: groupIds=$groupIds');
      await supabase.from('post_shares').insert([
        for (final groupId in groupIds)
          {
            'post_id': postId,
            'group_id': groupId,
            'user_id': userId,
            'shared_date': jstDateString(now),
            'shared_hour': now.hour,
          },
      ]);
      debugPrint('[post] ✅ post_shares insert 完了');
    }

    // ⚠️ 計測用イベント。この行だけを削除しないこと（send()機能ごと消すのはOK）
    Analytics.log('video_posted', {
      'post_id': postId,
      'group_count': groupIds.length,
      'retake_count': _ref.read(retakeCountProvider.notifier).count,
    });
    _ref.read(retakeCountProvider.notifier).reset();
    _ref.read(recordedVideoProvider.notifier).clear();
    debugPrint('[post] send() 完了');
  }
}
