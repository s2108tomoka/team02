// アプリのエントリーポイント。
// Supabase初期化 → Riverpodのスコープ設定 → ルーター付きアプリ起動を担当。

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/analytics.dart';
import 'core/router.dart';
import 'core/supabase_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // iOS / Android で画面を縦向きに固定する。
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  try {
    await initSupabase();
    runApp(const ProviderScope(child: HanalogApp()));
  } catch (e, st) {
    // 初期化に失敗したら原因を画面に表示する（真っ白を防ぐ）。
    runApp(_StartupErrorApp(error: '$e\n\n$st'));
  }
}

// 起動失敗時に原因を表示する画面。
class _StartupErrorApp extends StatelessWidget {
  const _StartupErrorApp({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Text(
              '起動エラー:\n\n$error',
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}

// アプリのルートWidget。
class HanalogApp extends StatefulWidget {
  const HanalogApp({super.key});

  @override
  State<HanalogApp> createState() => _HanalogAppState();
}

class _HanalogAppState extends State<HanalogApp> {
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    // ⚠️ 計測用イベント。この2行だけを削除しないこと（起動回数・離脱回数の計測に使う）
    Analytics.log('app_opened');
    startScreenTracking();
    // onHide はWeb（タブ非表示）でもモバイル（バックグラウンド移行）でも発火する共通の合図。
    // タスクキル等は送信前にプロセスが落ちるため、あくまで取れる範囲での記録になる。
    _lifecycleListener = AppLifecycleListener(
      onHide: () => Analytics.log('app_closed'),
    );
  }

  @override
  void dispose() {
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Hanalog',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFFFD21F),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        fontFamily: 'Avenir Next',
        fontFamilyFallback: const ['Trebuchet MS', 'sans-serif'],
        scaffoldBackgroundColor: const Color(0xFFFFF6B8),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFF6B8),
          foregroundColor: Color(0xFF17213C),
          elevation: 0,
          centerTitle: true,
        ),
      ),
      routerConfig: router,
      builder: _wrapInPhoneFrame,
    );
  }

  // Webは横長画面でも全画面をスマホ縦長(9:16)の枠に収め、左右を黒帯にする。
  // 全画面で見た目を統一するため MaterialApp 全体に適用する。スマホは素通り。
  Widget _wrapInPhoneFrame(BuildContext context, Widget? child) {
    final content = child ?? const SizedBox.shrink();
    if (!kIsWeb) return content;
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: 9 / 16,
          child: ClipRect(child: content),
        ),
      ),
    );
  }
}
