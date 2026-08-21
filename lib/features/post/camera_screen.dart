// 撮影画面。表示時にカメラを自動起動し、動画を撮影する。
// イン/アウトカメラ切替・タイマー設定も担当。撮影後は送信画面へ。

import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/navigation.dart';
import '../../core/video_filter_overlay.dart';
import '../../models/video_filter.dart';
import 'camera_web_api.dart';
import 'post_provider.dart';

class CameraScreen extends ConsumerStatefulWidget {
  const CameraScreen({super.key});

  @override
  ConsumerState<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends ConsumerState<CameraScreen> {
  List<CameraDescription> _cameras = const [];
  CameraController? _controller;
  int _cameraIndex = 0;
  bool _isRecording = false;
  bool _initializing = true;
  String? _error;

  // 撮影開始までのカウントダウン秒数（タイマー設定）。0なら即時。
  int _timerSeconds = 0;
  int _countdown = 0;
  Timer? _timer;

  // 録画は2秒で自動停止する（Hanalog風の短尺ログ）。
  static const _recordDuration = Duration(seconds: 2);
  Timer? _recordTimer;
  VideoFilter _selectedFilter = VideoFilter.none;

  @override
  void initState() {
    super.initState();
    _setupCameras();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _recordTimer?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  void _retry() {
    debugPrint('[camera] 再試行: カメラセットアップを再実行');
    setState(() {
      _error = null;
      _initializing = true;
    });
    _setupCameras();
  }

  Future<void> _setupCameras() async {
    debugPrint('[camera] セットアップ開始 platform=${kIsWeb ? "web" : "native"}');
    try {
      final List<CameraDescription> all;
      if (kIsWeb) {
        // Web: camera_web プラグインは availableCameras() が返した CameraDescription を
        // 内部レジストリに保持する。それを呼ばずに CameraController を作ると
        // cameraMissingMetadata エラーになる。
        //
        // 手順:
        //   1. JS ヘルパーでカメラのみ権限を取得（マイク不要）
        //   2. カメラ権限が確定した後で availableCameras() を呼ぶ
        //      → カメラはすでに granted なので video 部分は即時完了
        //      → マイクはダイアログが出るか即 NotAllowedError になる（ハングしない）
        debugPrint('[camera] Web: JS ヘルパーでカメラ権限を取得中...');
        await enumerateCamerasWebImpl(); // 戻り値不要・権限取得が目的
        debugPrint('[camera] カメラ権限確定 → availableCameras() でplugin状態を初期化中...');
        debugPrint('[camera] ※ マイク許可ダイアログが表示されたら「許可」してください');
        all = await availableCameras().timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            debugPrint('[camera] ⚠️ availableCameras() 20秒タイムアウト');
            debugPrint('[camera] 💡 開発時は以下で起動するとパーミッションを省略できます:');
            debugPrint(
              '[camera]    flutter run -d chrome '
              '--web-browser-flag="--use-fake-ui-for-media-stream"',
            );
            throw _CameraTimeoutException();
          },
        );
        debugPrint('[camera] ✅ availableCameras() 完了: ${all.length}台');
      } else {
        // native: 通常通り availableCameras() を使う
        debugPrint('[camera] availableCameras() 呼び出し中...');
        all = await availableCameras().timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            debugPrint('[camera] ⚠️ availableCameras() が 8秒でタイムアウト');
            throw _CameraTimeoutException();
          },
        );
        debugPrint('[camera] availableCameras() 完了');
        debugPrint('[camera] 検出されたカメラ数: ${all.length}');
        for (final c in all) {
          debugPrint('[camera]   - ${c.name} dir=${c.lensDirection}');
        }
      }

      if (all.isEmpty) {
        debugPrint('[camera] ⚠️ カメラが1台も見つからない');
        setState(() {
          _error = kIsWeb
              ? 'カメラが見つかりません。\n'
                    'ブラウザのURLバーにあるカメラアイコンをクリックして\n'
                    '「許可する」または「毎回確認する」に変更してください。'
              : '利用可能なカメラが見つかりません';
          _initializing = false;
        });
        return;
      }

      // iPhoneは背面が広角/超広角/望遠など複数返るため、
      // 背面・前面それぞれ1台ずつに絞って切替対象を [背面, 前面] に固定する。
      final back = all.where(
        (c) => c.lensDirection == CameraLensDirection.back,
      );
      final front = all.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      _cameras = [
        if (back.isNotEmpty) back.first,
        if (front.isNotEmpty) front.first,
      ];
      if (_cameras.isEmpty) _cameras = all;
      debugPrint(
        '[camera] 使用カメラ: 背面=${back.length}台, 前面=${front.length}台 '
        '→ 切替対象=${_cameras.length}台',
      );

      await _initController(0);
    } catch (e, st) {
      final msg = e.toString();
      debugPrint('[camera] ❌ セットアップ失敗: $msg');
      debugPrint('[camera] $st');

      final isTimeout = e is _CameraTimeoutException;
      final isMacOsTimeout = msg.contains('TIMEOUT');
      final isPermission =
          isTimeout ||
          isMacOsTimeout ||
          msg.contains('NotAllowedError') ||
          msg.contains('Permission') ||
          msg.contains('permission') ||
          msg.contains('denied');
      debugPrint(
        '[camera] timeout=$isTimeout macOsTimeout=$isMacOsTimeout '
        'permission=$isPermission',
      );
      setState(() {
        _error = isMacOsTimeout && kIsWeb
            ? 'macOS のカメラアクセスが Chrome に許可されていません。\n\n'
                  '【手順】\n'
                  '① Mac の「システム設定」を開く\n'
                  '② 「プライバシーとセキュリティ」→「カメラ」\n'
                  '③ 「Google Chrome」をオンにする\n'
                  '④ Chrome を再起動して「再試行」を押す'
            : isPermission && kIsWeb
            ? 'カメラの使用が許可されていません。\n\n'
                  '【手順】\n'
                  '① URLバー左の 🔒 をクリック\n'
                  '② 「カメラ」を「許可する」に変更\n'
                  '③ 「再試行」ボタンを押す'
            : 'カメラの起動に失敗しました: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _initController(int index) async {
    // iOSは複数のキャプチャセッションを同時に開けないため、
    // 新しいカメラを起動する前に必ず旧コントローラを破棄する（切替で死ぬのを防ぐ）。
    debugPrint('[camera] コントローラ初期化開始 index=$index');
    await _controller?.dispose();
    _controller = null;

    final cam = _cameras[index];
    debugPrint('[camera] 対象カメラ: ${cam.name} dir=${cam.lensDirection}');
    // Web はマイクパーミッションが取れない環境でも起動できるよう audio を無効にする。
    // マイクブロックで getUserMedia が失敗してカメラごと起動しなくなるのを防ぐ。
    final controller = CameraController(
      cam,
      ResolutionPreset.medium,
      enableAudio: !kIsWeb,
    );
    debugPrint('[camera] CameraController 作成 enableAudio=${!kIsWeb}');
    try {
      await controller.initialize();
      debugPrint(
        '[camera] ✅ コントローラ初期化成功 '
        'previewSize=${controller.value.previewSize} '
        'aspectRatio=${controller.value.aspectRatio.toStringAsFixed(2)}',
      );
      if (!mounted) {
        debugPrint('[camera] unmounted のため破棄');
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _cameraIndex = index;
        _initializing = false;
      });
    } catch (e, st) {
      debugPrint(
        '[camera] ❌ コントローラ初期化失敗 index=$index '
        'dir=${cam.lensDirection}: $e',
      );
      debugPrint('[camera] $st');
      if (!mounted) return;
      setState(() {
        _error = 'カメラの初期化に失敗しました: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras.length < 2 || _isRecording) return;
    final next = (_cameraIndex + 1) % _cameras.length;
    debugPrint('[camera] カメラ切替: $next');
    setState(() => _initializing = true);
    await _initController(next);
  }

  void _onShutterPressed() {
    debugPrint('[camera] シャッター押下 isRecording=$_isRecording');
    if (_isRecording) {
      _stopRecording();
      return;
    }
    if (_timerSeconds > 0) {
      _startCountdown();
    } else {
      _startRecording();
    }
  }

  void _startCountdown() {
    debugPrint('[camera] カウントダウン開始: $_timerSeconds 秒');
    setState(() => _countdown = _timerSeconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_countdown <= 1) {
        timer.cancel();
        setState(() => _countdown = 0);
        _startRecording();
      } else {
        setState(() => _countdown--);
      }
    });
  }

  Future<void> _startRecording() async {
    final controller = _controller;
    debugPrint('[camera] 録画開始試行 controller=${controller != null}');
    if (controller == null || _isRecording) return;
    try {
      await controller.startVideoRecording();
      debugPrint('[camera] ✅ 録画開始成功');
      setState(() => _isRecording = true);
      // 2秒経過で自動停止する。
      _recordTimer = Timer(_recordDuration, _stopRecording);
    } catch (e, st) {
      debugPrint('[camera] ❌ 録画開始失敗: $e');
      debugPrint('[camera] $st');
      setState(() => _error = '録画開始に失敗しました: $e');
    }
  }

  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final controller = _controller;
    debugPrint(
      '[camera] 録画停止試行 controller=${controller != null} '
      'isRecording=$_isRecording',
    );
    if (controller == null || !_isRecording) return;
    try {
      final file = await controller.stopVideoRecording();
      debugPrint(
        '[camera] ✅ 録画停止成功 path=${file.path} '
        'mimeType=${file.mimeType}',
      );
      setState(() => _isRecording = false);
      ref.read(retakeCountProvider.notifier).increment();
      ref
          .read(recordedVideoProvider.notifier)
          .set(
            RecordedVideo(
              file: file,
              needsFlip: _needsFlip,
              filter: _selectedFilter,
            ),
          );
      debugPrint(
        '[camera] 送信画面へ遷移 needsFlip=$_needsFlip filter=${_selectedFilter.name}',
      );
      if (mounted) context.push('/send');
    } catch (e, st) {
      debugPrint('[camera] ❌ 録画停止失敗: $e');
      debugPrint('[camera] $st');
      setState(() {
        _isRecording = false;
        _error = '録画停止に失敗しました: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _error != null
            ? _ErrorView(message: _error!, onRetry: _retry)
            : _initializing || _controller == null
            ? const Center(child: CircularProgressIndicator())
            : _buildCameraView(),
      ),
    );
  }

  // 縦長フレームに横向きで撮影する（プレビューは画面いっぱいにcover表示）。
  Widget _buildCameraView() {
    final controller = _controller!;

    return Stack(
      children: [
        Positioned.fill(
          child: withVideoFilter(_buildPreview(controller), _selectedFilter),
        ),
        // 撮影中・待機中は中央に横向きで現在時刻を表示する。
        // カウントダウン中は数字と被るため時刻は隠す。
        if (_countdown == 0)
          Center(
            child: RotatedBox(
              quarterTurns: 1,
              child: Text(
                _currentTimeLabel,
                style: const TextStyle(
                  fontSize: 64,
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                  shadows: [Shadow(blurRadius: 12, color: Colors.black54)],
                ),
              ),
            ),
          )
        else
          Center(
            child: Text(
              '$_countdown',
              style: const TextStyle(
                fontSize: 96,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
        Positioned(
          top: 8,
          right: 8,
          child: _CircleButton(
            icon: Icons.close,
            onTap: () => context.backOrHome(),
          ),
        ),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildControls()),
      ],
    );
  }

  // カメラプレビューを画面いっぱいにcover表示する。
  // Web のカメラは横長で返るため、縦長画面に合わせて切り抜いて表示する。
  // スマホは従来通りスケール係数で歪みなくcover表示する。
  Widget _buildPreview(CameraController controller) {
    if (kIsWeb) {
      // 横長のWebカメラ映像を、縦長枠に回転させずcoverで切り抜いて表示する（鏡のまま）。
      final preview = controller.value.previewSize;
      return ClipRect(
        child: FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: preview?.width ?? 16,
            height: preview?.height ?? 9,
            child: CameraPreview(controller),
          ),
        ),
      );
    }
    final mediaSize = MediaQuery.of(context).size;
    final scale = 1 / (controller.value.aspectRatio * mediaSize.aspectRatio);
    return ClipRect(
      child: Transform.scale(
        scale: scale,
        alignment: Alignment.center,
        child: Center(child: CameraPreview(controller)),
      ),
    );
  }

  // Android前面カメラはファイル自体が上下逆に記録されるため、再生側で補正させる。
  bool get _needsFlip {
    if (kIsWeb || _cameras.isEmpty) return false;
    return defaultTargetPlatform == TargetPlatform.android &&
        _cameras[_cameraIndex].lensDirection == CameraLensDirection.front;
  }

  String get _currentTimeLabel {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildControls() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black54],
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _TimerButton(
            seconds: _timerSeconds,
            enabled: !_isRecording && _countdown == 0,
            onTap: _cycleTimer,
          ),
          IconButton(
            tooltip: 'フィルター: ${_selectedFilter.label}',
            iconSize: 30,
            color: Colors.white,
            icon: const Icon(Icons.auto_awesome),
            onPressed: _isRecording ? null : _showFilterSheet,
          ),
          GestureDetector(
            onTap: _countdown > 0 ? null : _onShutterPressed,
            child: Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _isRecording ? Colors.red : Colors.white,
                border: Border.all(color: Colors.white, width: 4),
              ),
              child: Icon(
                _isRecording ? Icons.stop : Icons.videocam,
                color: _isRecording ? Colors.white : Colors.black,
              ),
            ),
          ),
          IconButton(
            iconSize: 32,
            color: Colors.white,
            icon: const Icon(Icons.cameraswitch),
            onPressed: _cameras.length < 2 || _isRecording
                ? null
                : _switchCamera,
          ),
        ],
      ),
    );
  }

  // タイマー設定を 0→3→5→10→0 と切り替える。
  void _cycleTimer() {
    const options = [0, 3, 5, 10];
    final next = options[(options.indexOf(_timerSeconds) + 1) % options.length];
    setState(() => _timerSeconds = next);
  }

  void _showFilterSheet() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.white,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'フィルター',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  for (final filter in VideoFilter.values)
                    ChoiceChip(
                      label: Text(filter.label),
                      selected: filter == _selectedFilter,
                      avatar: filter == VideoFilter.none
                          ? null
                          : CircleAvatar(backgroundColor: filter.previewColor),
                      onSelected: (_) {
                        setState(() => _selectedFilter = filter);
                        Navigator.of(sheetContext).pop();
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// 半透明の丸型アイコンボタン（閉じるボタン用）。
class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        child: Icon(icon, size: 22, color: Colors.black87),
      ),
    );
  }
}

class _TimerButton extends StatelessWidget {
  const _TimerButton({
    required this.seconds,
    required this.enabled,
    required this.onTap,
  });

  final int seconds;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: enabled ? onTap : null,
      icon: const Icon(Icons.timer, color: Colors.white),
      label: Text(
        seconds == 0 ? 'OFF' : '${seconds}s',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 24),
          const Icon(Icons.videocam_off, size: 48, color: Colors.white54),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('再試行'),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// availableCameras() がタイムアウトしたことを示す内部例外。
class _CameraTimeoutException implements Exception {}
