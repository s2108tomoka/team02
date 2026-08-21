// 送信画面。撮影動画をプレビューし、送信先グループを選んで投稿する。

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_platform.dart';
import '../../core/navigation.dart';
import '../../core/video_filter_overlay.dart';
import '../../models/group.dart';
import '../../models/sticker_overlay.dart';
import '../../models/video_filter.dart';
import 'post_provider.dart';
import 'recorded_video_view.dart';
import 'video_preview_factory.dart';

class SendScreen extends ConsumerStatefulWidget {
  const SendScreen({super.key});

  @override
  ConsumerState<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends ConsumerState<SendScreen> {
  VideoPlayerController? _videoController;
  final Set<String> _selectedGroupIds = {};
  // 自分のログへの投稿。初期状態でオン。
  bool _postToSelf = true;
  bool _sending = false;
  final List<StickerOverlay> _stickers = [];

  static const _availableStickers = [
    '⭐',
    '❤️',
    '🔥',
    '😊',
    '🎉',
    '👍',
    '✨',
    '🌈',
    '🎵',
    '🌟',
    '💫',
    '🎯',
  ];

  @override
  void initState() {
    super.initState();
    final video = ref.read(recordedVideoProvider);
    if (video != null) _initPreview(video.file);
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  Future<void> _initPreview(XFile video) async {
    debugPrint('[send] プレビュー初期化: ${video.path}');
    final controller = createPreviewController(video.path);
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      debugPrint('[send] ✅ プレビュー再生開始');
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
    } catch (e, st) {
      debugPrint('[send] ❌ プレビュー初期化失敗: $e');
      debugPrint('[send] $st');
      await controller.dispose();
    }
  }

  // 撮影画面へ戻る。動画は破棄する。
  void _cancel() {
    ref.read(recordedVideoProvider.notifier).clear();
    context.backOrHome();
  }

  Future<void> _send() async {
    final video = ref.read(recordedVideoProvider);
    debugPrint(
      '[send] _send() 呼び出し '
      'video=${video?.file.path} '
      'postToSelf=$_postToSelf '
      'selectedGroups=${_selectedGroupIds.toList()} '
      'stickers=${_stickers.length}件',
    );
    if (video == null || _sending) return;
    if (!_postToSelf && _selectedGroupIds.isEmpty) return;

    setState(() => _sending = true);
    try {
      await ref
          .read(postControllerProvider)
          .send(
            video: video.file,
            groupIds: _selectedGroupIds.toList(),
            needsFlip: video.needsFlip,
            stickers: _stickers,
            filter: video.filter,
          );
      debugPrint('[send] ✅ 送信完了 → /home へ遷移');
      if (mounted) context.go('/home');
    } catch (e, st) {
      debugPrint('[send] ❌ 送信失敗: $e');
      debugPrint('[send] $st');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('送信に失敗しました: $e')));
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final video = ref.watch(recordedVideoProvider);
    if (video == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('送信')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('動画がありません'),
              TextButton(
                onPressed: () => context.backOrHome(),
                child: const Text('撮影画面へ戻る'),
              ),
            ],
          ),
        ),
      );
    }

    final targets = ref.watch(sendTargetsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('送信'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _sending ? null : _cancel,
        ),
      ),
      body: Column(
        children: [
          _buildPreview(),
          const Divider(height: 1),
          const Padding(
            padding: EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('送信先', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
          _buildSelfTile(),
          const Divider(height: 1),
          Expanded(
            child: targets.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('グループの取得に失敗しました: $e')),
              data: (data) => _buildGroupList(data),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildPreview() {
    final controller = _videoController;
    final needsFlip = ref.watch(recordedVideoProvider)?.needsFlip ?? false;
    final filter = ref.watch(recordedVideoProvider)?.filter ?? VideoFilter.none;
    return Column(
      children: [
        Container(
          color: Colors.black,
          width: double.infinity,
          child: controller != null && controller.value.isInitialized
              // 撮影時(縦長フレーム)の見た目を90度回転した横長(16:9)で表示する。
              ? AspectRatio(
                  aspectRatio: 16 / 9,
                  child: ClipRect(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        withVideoFilter(
                          RecordedVideoView(
                            controller: controller,
                            needsFlip: needsFlip,
                            recordedPlatform: currentPlatform,
                          ),
                          filter,
                        ),
                        _buildStickerLayer(),
                      ],
                    ),
                  ),
                )
              : const SizedBox(
                  height: 220,
                  child: Center(child: CircularProgressIndicator()),
                ),
        ),
        _buildStickerPicker(),
      ],
    );
  }

  // ステッカー選択パレット。タップで動画中央に追加する。
  Widget _buildStickerPicker() {
    return Container(
      color: Colors.black87,
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          for (final emoji in _availableStickers)
            GestureDetector(
              onTap: _sending
                  ? null
                  : () => setState(
                      () => _stickers.add(
                        StickerOverlay(emoji: emoji, x: 0.5, y: 0.5),
                      ),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(emoji, style: const TextStyle(fontSize: 28)),
              ),
            ),
        ],
      ),
    );
  }

  // ドラッグ移動・長押し削除ができるステッカー重ね表示。
  Widget _buildStickerLayer() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Stack(
          children: [
            for (int i = 0; i < _stickers.length; i++)
              Positioned(
                left: _stickers[i].x * constraints.maxWidth - 16,
                top: _stickers[i].y * constraints.maxHeight - 16,
                child: GestureDetector(
                  onPanUpdate: _sending
                      ? null
                      : (d) {
                          setState(() {
                            final s = _stickers[i];
                            _stickers[i] = s.copyWith(
                              x: (s.x + d.delta.dx / constraints.maxWidth)
                                  .clamp(0.0, 1.0),
                              y: (s.y + d.delta.dy / constraints.maxHeight)
                                  .clamp(0.0, 1.0),
                            );
                          });
                        },
                  onLongPress: _sending
                      ? null
                      : () => setState(() => _stickers.removeAt(i)),
                  child: Text(
                    _stickers[i].emoji,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  // 「自分のログへあげる」選択肢。常に表示する。
  Widget _buildSelfTile() {
    return CheckboxListTile(
      value: _postToSelf,
      onChanged: _sending
          ? null
          : (checked) => setState(() => _postToSelf = checked ?? false),
      secondary: const Icon(Icons.person_outline),
      title: const Text('自分のログへあげる'),
    );
  }

  Widget _buildGroupList(SendTargets data) {
    if (data.groups.isEmpty) {
      return const Center(child: Text('参加中のグループがありません'));
    }
    return ListView(
      children: [for (final group in data.groups) _buildGroupTile(group)],
    );
  }

  Widget _buildGroupTile(Group group) {
    final selected = _selectedGroupIds.contains(group.id);
    return CheckboxListTile(
      value: selected,
      onChanged: _sending
          ? null
          : (checked) {
              setState(() {
                if (checked == true) {
                  _selectedGroupIds.add(group.id);
                } else {
                  _selectedGroupIds.remove(group.id);
                }
              });
            },
      title: Text(group.name),
    );
  }

  Widget _buildBottomBar() {
    final canSend = (_postToSelf || _selectedGroupIds.isNotEmpty) && !_sending;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: FilledButton.icon(
          onPressed: canSend ? _send : null,
          icon: _sending
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: Text(_sending ? '送信中...' : '送信'),
        ),
      ),
    );
  }
}
