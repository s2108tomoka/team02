// グループ詳細画面。指定した日付・時間帯のメンバー全員の投稿を一覧表示する。
// 投稿済みは動画カード、未投稿は枠（プレースホルダー）で表示する。
// 時間移動（左右タップ）／日付移動（左右スワイプ）／メンバー・招待も担当。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/analytics.dart';
import '../../core/cached_video.dart';
import '../../core/animated_flower.dart';
import '../../core/jst.dart';
import '../../models/app_user.dart';
import '../../models/group.dart';
import '../home/home_provider.dart';
import '../post/recorded_video_view.dart';
import 'group_provider.dart';

// メンバー頭文字アバターの色。
const _avatarColors = [
  Color(0xFF4FC3F7),
  Color(0xFF81C784),
  Color(0xFFFFB74D),
  Color(0xFFBA68C8),
  Color(0xFFE57373),
  Color(0xFF4DB6AC),
  Color(0xFF7986CB),
  Color(0xFFF06292),
];

Color _colorFor(String key) =>
    _avatarColors[key.hashCode.abs() % _avatarColors.length];

double _flowerPhase(String key) => (key.hashCode.abs() % 100) / 100;

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key, required this.groupId});

  // 表示対象のグループID（ルートの /group/:id から受け取る）。
  final String groupId;

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  late DateTime _date;
  late int _hour;

  @override
  void initState() {
    super.initState();
    final now = jstNow();
    _date = DateTime(now.year, now.month, now.day);
    _hour = now.hour;
  }

  void _changeHour(int delta) {
    final next = _hour + delta;
    if (next < 0 || next > 23) return;
    setState(() => _hour = next);
  }

  void _changeDate(int deltaDays) {
    setState(() => _date = _date.add(Duration(days: deltaDays)));
  }

  String get _slotLabel => '${_hour.toString().padLeft(2, '0')}:00';

  // 今日・昨日・それ以外は曜日で表す（絶対日付は表示しない）。
  String get _dayLabel {
    final now = jstNow();
    final today = DateTime(now.year, now.month, now.day);
    final diff = today.difference(_date).inDays;
    if (diff == 0) return '今日';
    if (diff == 1) return '昨日';
    const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
    return '${weekdays[_date.weekday - 1]}曜日';
  }

  // 未来へは進めない。今日より前の日付のときだけ翌日へ移動できる。
  bool get _canGoForwardDate {
    final now = jstNow();
    final today = DateTime(now.year, now.month, now.day);
    return _date.isBefore(today);
  }

  // 今日の場合は現在時刻より先の時間帯へは進めない。
  bool get _canGoForwardHour {
    final now = jstNow();
    final today = DateTime(now.year, now.month, now.day);
    if (_date == today) return _hour < now.hour;
    return _hour < 23;
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    final membersAsync = ref.watch(groupMembersProvider(widget.groupId));
    final args = GroupPostsArgs(
      groupId: widget.groupId,
      date: _date,
      hour: _hour,
    );
    final postsAsync = ref.watch(groupPostsProvider(args));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          groupAsync.maybeWhen(data: (g) => g.name, orElse: () => 'グループ'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'グループ情報',
            onPressed: () => _showInfoSheet(groupAsync.value),
          ),
        ],
      ),
      body: Column(
        children: [
          // 相対的な日付ラベル（今日/昨日/曜日）のみ表示する。
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              _dayLabel,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  // 左半分タップ→前の時間 / 右半分タップ→次の時間（未来は不可）。
                  onTapUp: (details) {
                    if (details.localPosition.dx < constraints.maxWidth / 2) {
                      if (_hour > 0) _changeHour(-1);
                    } else if (_canGoForwardHour) {
                      _changeHour(1);
                    }
                  },
                  // 昨日が左・翌日が右のイメージ。右スワイプ→前日 / 左スワイプ→翌日。
                  onHorizontalDragEnd: (details) {
                    final v = details.primaryVelocity ?? 0;
                    if (v < 0) {
                      if (_canGoForwardDate) _changeDate(1);
                    } else if (v > 0) {
                      _changeDate(-1);
                    }
                  },
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: KeyedSubtree(
                      key: ValueKey('${_date.toIso8601String()}-$_hour'),
                      child: _buildContent(membersAsync, postsAsync),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // メンバーと投稿の両方が揃ったら、メンバー全員分のカードを表示する。
  Widget _buildContent(
    AsyncValue<List<AppUser>> membersAsync,
    AsyncValue<List<GroupPost>> postsAsync,
  ) {
    if (membersAsync.isLoading || postsAsync.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (membersAsync.hasError) {
      return Center(child: Text('メンバーの取得に失敗しました: ${membersAsync.error}'));
    }
    if (postsAsync.hasError) {
      return Center(child: Text('投稿の取得に失敗しました: ${postsAsync.error}'));
    }

    final members = membersAsync.value ?? const [];
    final posts = postsAsync.value ?? const [];
    final postedUserIds = {for (final p in posts) p.userId};

    if (members.isEmpty) {
      return const Center(child: Text('メンバーがいません'));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        for (final post in posts)
          _MemberPostCard(
            key: ValueKey(post.postId),
            post: post,
            slotLabel: _slotLabel,
          ),
        for (final member in members)
          if (!postedUserIds.contains(member.id))
            _EmptyMemberCard(member: member, slotLabel: _slotLabel),
      ],
    );
  }

  void _showInfoSheet(Group? group) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (group != null) ...[
                  Text('招待コード', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 4),
                  SelectableText(
                    group.inviteCode,
                    style: Theme.of(
                      context,
                    ).textTheme.headlineSmall?.copyWith(letterSpacing: 2),
                  ),
                  const Divider(height: 24),
                ],
                Text('メンバー', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 8),
                Consumer(
                  builder: (context, ref, _) {
                    final membersAsync = ref.watch(
                      groupMembersProvider(widget.groupId),
                    );
                    return membersAsync.when(
                      data: (members) =>
                          Column(children: members.map(_memberTile).toList()),
                      loading: () => const Padding(
                        padding: EdgeInsets.all(8),
                        child: CircularProgressIndicator(),
                      ),
                      error: (e, _) => Text('メンバー取得エラー: $e'),
                    );
                  },
                ),
                const Divider(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    icon: const Icon(Icons.exit_to_app),
                    label: const Text('グループを脱退する'),
                    onPressed: () => _confirmLeaveGroup(context),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmLeaveGroup(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('グループから脱退しますか？'),
        content: const Text('脱退すると、このグループの動画一覧が見られなくなります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('脱退する'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (context.mounted) {
      Navigator.of(context).pop();
    }

    try {
      await ref.read(groupServiceProvider).leaveGroup(widget.groupId);
      ref.invalidate(myGroupsProvider);
      
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('グループから脱退しました')),
        );
        context.go('/home');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('脱退に失敗しました: $e')),
        );
      }
    }
  }

  Widget _memberTile(AppUser member) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _Avatar(name: member.name, radius: 18),
      title: Text(member.name),
    );
  }
}

// メンバーの頭文字アバター。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.name, this.radius = 16});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: _colorFor(name),
      foregroundColor: Colors.white,
      child: Text(
        name.isNotEmpty ? name[0] : '?',
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: radius * 0.8),
      ),
    );
  }
}

// 投稿済みメンバーのカード。動画を自動再生し、投稿者名・時刻を重ねる。
// 縦で撮影した動画を90度左回転して横向きで表示する。
class _MemberPostCard extends StatefulWidget {
  const _MemberPostCard({
    super.key,
    required this.post,
    required this.slotLabel,
  });

  final GroupPost post;
  final String slotLabel;

  @override
  State<_MemberPostCard> createState() => _MemberPostCardState();
}

class _MemberPostCardState extends State<_MemberPostCard> {
  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      // キャッシュ済みなら即時、無ければ取得してから再生（再取得を防ぐ）。
      final controller = await createCachedVideoController(
        widget.post.videoUrl,
      );
      _controller = controller;
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _initialized = true);
      // ⚠️ 計測用イベント。この行だけを削除しないこと（再生機能ごと消すのはOK）
      Analytics.log('video_played', {'post_id': widget.post.postId});
      await controller.play();
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    // タップは時間移動に使うため、カード自体ではタップを受けない（自動再生・ループ）。
    return _CardFrame(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_failed)
            const ColoredBox(
              color: Colors.black87,
              child: Center(
                child: Icon(
                  Icons.error_outline,
                  color: Colors.white54,
                  size: 40,
                ),
              ),
            )
          else if (_initialized && controller != null)
            RecordedVideoView(
              controller: controller,
              needsFlip: widget.post.needsFlip,
              recordedPlatform: widget.post.platform,
            )
          else
            const ColoredBox(
              color: Colors.black87,
              child: Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),
          _NameOverlay(name: widget.post.userName),
          _TimeOverlay(label: widget.slotLabel),
        ],
      ),
    );
  }
}

// 未投稿メンバーのプレースホルダーカード。
class _EmptyMemberCard extends StatelessWidget {
  const _EmptyMemberCard({required this.member, required this.slotLabel});

  final AppUser member;
  final String slotLabel;

  @override
  Widget build(BuildContext context) {
    return _CardFrame(
      filled: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: 34,
            left: 0,
            right: 0,
            height: 76,
            child: AnimatedFlower(
              size: 52,
              width: double.infinity,
              height: 76,
              phase: _flowerPhase(member.id),
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(top: 72),
              child: Text(
                'まだ投稿していません',
                style: TextStyle(
                  color: const Color(0xFF527878),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          _NameOverlay(name: member.name, dark: false),
          _TimeOverlay(label: slotLabel, dark: false),
        ],
      ),
    );
  }
}

// カードの共通の枠（角丸・16:10・余白）。filled=false は未投稿用の薄い背景。
class _CardFrame extends StatelessWidget {
  const _CardFrame({required this.child, this.filled = true});

  final Widget child;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Container(
          decoration: BoxDecoration(
            color: filled ? Colors.black : const Color(0xFFE9FBF8),
            border: filled
                ? null
                : Border.all(color: const Color(0xFF9FE5E0), width: 1.5),
            borderRadius: BorderRadius.circular(20),
          ),
          child: AspectRatio(aspectRatio: 16 / 10, child: child),
        ),
      ),
    );
  }
}

// カード左上の投稿者名＋アバター。
class _NameOverlay extends StatelessWidget {
  const _NameOverlay({required this.name, this.dark = true});

  final String name;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 12,
      top: 12,
      child: Row(
        children: [
          _Avatar(name: name, radius: 14),
          const SizedBox(width: 8),
          Text(
            name,
            style: TextStyle(
              color: dark ? Colors.white : Colors.black87,
              fontWeight: FontWeight.bold,
              shadows: dark
                  ? const [Shadow(blurRadius: 6, color: Colors.black54)]
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

// カード中央の時刻ラベル。
class _TimeOverlay extends StatelessWidget {
  const _TimeOverlay({required this.label, this.dark = true});

  final String label;
  final bool dark;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        label,
        style: TextStyle(
          color: dark ? Colors.white : Colors.grey[500],
          fontSize: 28,
          fontWeight: FontWeight.w900,
          shadows: dark
              ? const [Shadow(blurRadius: 8, color: Colors.black54)]
              : null,
        ),
      ),
    );
  }
}
