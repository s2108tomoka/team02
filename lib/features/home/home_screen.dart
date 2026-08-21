// ホーム画面。自動再生Vlogフィードとグループ一覧を表示する。
// フローティングナビとブランドヘッダーを備えたメイン画面。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/cached_video.dart';
import '../../core/animated_flower.dart';
import '../../core/double_tap_heart.dart';
import '../../models/group.dart';
import '../../models/post.dart';
import '../auth/auth_provider.dart';
import '../post/recorded_video_view.dart';
import 'home_provider.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postsAsync = ref.watch(myPostsProvider);
    final groupsAsync = ref.watch(myGroupsProvider);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: () async {
                ref.invalidate(myPostsProvider);
                ref.invalidate(myGroupsProvider);
                await Future.wait([
                  ref.read(myPostsProvider.future),
                  ref.read(myGroupsProvider.future),
                ]);
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 80),
                children: [
                  _Header(
                    onAddGroup: () => _showGroupMenu(context),
                    onMore: () => _showMoreMenu(context, ref),
                  ),
                  const SizedBox(height: 8),
                  postsAsync.when(
                    data: (posts) {
                      if (posts.isEmpty) {
                        return const _EmptyState(
                          icon: Icons.videocam_off_outlined,
                          message: 'まだVlogがありません',
                          animatedFlower: true,
                        );
                      }
                      return _VlogFeed(posts: posts);
                    },
                    loading: () => const _LoadingIndicator(),
                    error: (e, _) =>
                        _ErrorMessage(text: 'Vlogの取得に失敗: $e'),
                  ),
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _GroupsSection(groupsAsync: groupsAsync),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 16,
              child: const Center(child: _FloatingBottomBar()),
            ),
          ],
        ),
      ),
    );
  }

  void _showGroupMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add),
              title: const Text('グループ作成'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/group/create');
              },
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('グループ参加'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/group/join');
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreMenu(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: const Text('プロフィール'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/profile');
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('ログアウト'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmLogout(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('ログアウトしますか？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('ログアウト'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(authControllerProvider.notifier).signOut();
    if (context.mounted) context.go('/login');
  }
}

// ブランドヘッダー。「HANALOG」ロゴと丸型アクションボタンを配置する。
class _Header extends StatelessWidget {
  const _Header({required this.onAddGroup, required this.onMore});

  final VoidCallback onAddGroup;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'HANALOG',
              overflow: TextOverflow.clip,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                fontStyle: FontStyle.italic,
                color: Color(0xFF2ECDB0),
                letterSpacing: 1,
              ),
            ),
          ),
          _CircleIconButton(icon: Icons.add, onTap: onAddGroup),
          const SizedBox(width: 8),
          _CircleIconButton(icon: Icons.more_horiz, onTap: onMore),
        ],
      ),
    );
  }
}

// 丸型のアイコンボタン。ヘッダー右側のアクション用。
class _CircleIconButton extends StatelessWidget {
  const _CircleIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey[200],
        ),
        child: Icon(icon, size: 20, color: Colors.black87),
      ),
    );
  }
}

// Vlogを自動再生し、終了したら次の動画へ進むフィード。
// 1件ならループ再生、複数件なら順番に再生する。
class _VlogFeed extends StatefulWidget {
  const _VlogFeed({required this.posts});

  final List<Post> posts;

  @override
  State<_VlogFeed> createState() => _VlogFeedState();
}

class _VlogFeedState extends State<_VlogFeed> {
  int _currentIndex = 0;
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _hasError = false;
  bool _transitioning = false;
  int _heartSeed = 0;
  int _loadGen = 0;

  @override
  void initState() {
    super.initState();
    _loadVideo(0);
  }

  @override
  void didUpdateWidget(_VlogFeed oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.posts.length != oldWidget.posts.length) {
      _loadVideo(0);
    }
  }

  Future<void> _loadVideo(int index) async {
    final gen = ++_loadGen;
    _transitioning = false;

    // 初回（表示する動画がまだ無い）だけスピナーを出す。
    // 切り替え時は前の動画を表示したまま、次の準備ができてから差し替える。
    final isFirst = _controller == null;
    if (isFirst && mounted) {
      setState(() {
        _initialized = false;
        _hasError = false;
      });
    }

    try {
      // キャッシュ済みなら即時、無ければ取得してから再生（再取得を防ぐ）。
      final controller =
          await createCachedVideoController(widget.posts[index].videoUrl);
      await controller.initialize();
      if (!mounted || gen != _loadGen) {
        await controller.dispose();
        return;
      }
      if (widget.posts.length == 1) {
        await controller.setLooping(true);
      } else {
        controller.addListener(_checkCompletion);
      }

      // 新しい動画の準備が整ってから旧コントローラを破棄する（黒画面を防ぐ）。
      final old = _controller;
      old?.removeListener(_checkCompletion);
      setState(() {
        _controller = controller;
        _currentIndex = index;
        _initialized = true;
        _hasError = false;
      });
      await controller.play();
      await old?.dispose();
      _prefetchNext(index);
    } catch (e) {
      debugPrint('動画の読み込みに失敗: $e');
      if (!mounted || gen != _loadGen) return;
      setState(() => _hasError = true);
      if (widget.posts.length > 1) {
        Future.delayed(const Duration(seconds: 2), _playNext);
      }
    }
  }

  // 次に再生する動画を裏でキャッシュに載せ、切り替えをスムーズにする。
  void _prefetchNext(int currentIndex) {
    if (widget.posts.length < 2) return;
    final nextIndex = (currentIndex + 1) % widget.posts.length;
    prefetchVideo(widget.posts[nextIndex].videoUrl);
  }

  void _checkCompletion() {
    if (_transitioning) return;
    final c = _controller;
    if (c == null || !_initialized) return;
    final v = c.value;
    if (v.duration > Duration.zero &&
        v.position >= v.duration - const Duration(milliseconds: 200) &&
        !v.isPlaying) {
      _transitioning = true;
      c.removeListener(_checkCompletion);
      _playNext();
    }
  }

  void _playNext() {
    if (!mounted || widget.posts.isEmpty) return;
    _loadVideo((_currentIndex + 1) % widget.posts.length);
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null || !_initialized) return;
    setState(() {
      c.value.isPlaying ? c.pause() : c.play();
    });
  }

  @override
  void dispose() {
    _controller?.removeListener(_checkCompletion);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final total = widget.posts.length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _togglePlayPause,
          onDoubleTap: () => setState(() => _heartSeed++),
          child: AspectRatio(
            // ホームでは横長のスリムなカードで表示する（撮影は縦長・横向き）。
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_hasError)
                  Container(
                    color: Colors.black87,
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.error_outline,
                              size: 40, color: Colors.white54),
                          SizedBox(height: 8),
                          Text('動画を読み込めませんでした',
                              style: TextStyle(color: Colors.white54)),
                        ],
                      ),
                    ),
                  )
                else if (_initialized && controller != null)
                  // 縦で撮影した動画を90度回転して横向きで表示する
                  // （送信プレビュー・グループ詳細と向きを揃える）。
                  RecordedVideoView(
                    controller: controller,
                    needsFlip: widget.posts[_currentIndex].needsFlip,
                    recordedPlatform: widget.posts[_currentIndex].platform,
                  )
                else
                  Container(
                    color: Colors.black87,
                    child: const Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
                  ),
                if (_initialized &&
                    controller != null &&
                    !controller.value.isPlaying)
                  const Center(
                    child: Icon(Icons.play_circle_fill,
                        size: 64, color: Colors.white70),
                  ),
                if (_heartSeed > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: HeartBurst(key: ValueKey(_heartSeed)),
                      ),
                    ),
                  ),
                const Positioned(
                  left: 16,
                  bottom: 24,
                  child: Text(
                    'ログ',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      shadows: [Shadow(blurRadius: 8, color: Colors.black54)],
                    ),
                  ),
                ),
                if (total > 1)
                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 8,
                    child: Row(
                      children: List.generate(
                        total,
                        (i) => Expanded(
                          child: Container(
                            height: 3,
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: i == _currentIndex
                                  ? Colors.white
                                  : Colors.white38,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// 参加中グループ一覧。タップでグループ詳細へ遷移する。
class _GroupsSection extends StatelessWidget {
  const _GroupsSection({required this.groupsAsync});

  final AsyncValue<List<Group>> groupsAsync;

  @override
  Widget build(BuildContext context) {
    return groupsAsync.when(
      data: (groups) {
        if (groups.isEmpty) {
          return const _EmptyState(
            icon: Icons.group_outlined,
            message: '参加中のグループがありません',
          );
        }
        return Column(
          children: [for (final group in groups) _GroupCard(group: group)],
        );
      },
      loading: () => const _LoadingIndicator(),
      error: (e, _) => _ErrorMessage(text: 'グループの取得に失敗: $e'),
    );
  }
}

// グループ1件のカード。アバター・グループ名を丸枠で表示する。
class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final Group group;

  static const _avatarColors = [
    Color(0xFF4FC3F7),
    Color(0xFF81C784),
    Color(0xFFFFB74D),
    Color(0xFFBA68C8),
    Color(0xFFE57373),
    Color(0xFF4DB6AC),
    Color(0xFF7986CB),
    Color(0xFFF06292),
  ];

  @override
  Widget build(BuildContext context) {
    final color =
        _avatarColors[group.name.hashCode.abs() % _avatarColors.length];

    return GestureDetector(
      onTap: () => context.push('/group/${group.id}'),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: color,
              foregroundColor: Colors.white,
              child: Text(
                group.name.isNotEmpty ? group.name[0] : '?',
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                group.name,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

// 画面下部のフローティングナビゲーションバー。
class _FloatingBottomBar extends StatelessWidget {
  const _FloatingBottomBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => context.push('/camera'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Text(
                'カメラ',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Text(
              'ログ',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
            ),
          ),
        ],
      ),
    );
  }
}

// 一覧が空のときに表示する共通ウィジェット。
class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.icon,
    required this.message,
    this.animatedFlower = false,
  });

  final IconData icon;
  final String message;
  final bool animatedFlower;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          if (animatedFlower)
            const AnimatedFlower(size: 56, width: double.infinity, height: 120)
          else
            Icon(icon, size: 48, color: Colors.grey[400]),
          const SizedBox(height: 8),
          Text(message, style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }
}

class _LoadingIndicator extends StatelessWidget {
  const _LoadingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 32),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(text, style: const TextStyle(color: Colors.red)),
    );
  }
}
