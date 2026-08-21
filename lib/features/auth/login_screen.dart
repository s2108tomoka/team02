// ログイン画面。メールアドレスとパスワードでのログイン / 新規登録を行う。
// 1画面でモードを切り替える（新規登録時はパスワード確認欄を表示）。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_errors.dart';
import 'auth_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  // ライト/ダーク共通の色（入力欄・ボタン・リンクはモードを問わず視認性が高いため固定）。
  static const _navy = Color(0xFF17213C);
  static const _yellow = Color(0xFFFFD21F);
  static const _yellowLight = Color(0xFFFFFBE3);
  static const _pink = Color(0xFFFF4F81);

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  // true: 新規登録モード / false: ログインモード
  bool _isSignUp = false;
  // パスワードを伏せ字にするか（目のアイコンで切替）。
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  // ログイン/新規登録を切り替える。入力中の確認欄はクリアする。
  void _toggleMode() {
    setState(() {
      _isSignUp = !_isSignUp;
      _confirmController.clear();
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final controller = ref.read(authControllerProvider.notifier);

    if (_isSignUp) {
      await controller.signUpWithEmail(email, password);
    } else {
      await controller.signInWithEmail(email, password);
    }

    if (!mounted) return;
    // エラーは ref.listen 側でSnackBar表示する。
    if (ref.read(authControllerProvider).hasError) return;

    // メール確認は使わない設定なので、成功すれば即セッションが張られる。
    // スプラッシュで「プロフィール未登録→/profile/setup / 登録済み→/home」を振り分ける。
    context.go('/splash');
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authControllerProvider);
    final isLoading = authState.isLoading;
    final palette = _LoginPalette.of(context);

    ref.listen(authControllerProvider, (prev, next) {
      if (next.hasError) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(authErrorMessage(next.error!))));
      }
    });

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: palette.bgGradient,
          ),
        ),
        child: Stack(
          children: [
            Positioned.fill(child: _TropicalBackground(palette: palette)),
            const Positioned(
              top: 42,
              right: 24,
              child: _FlowerSticker(emoji: '🌺', size: 42, angle: -.16),
            ),
            const Positioned(
              top: 150,
              left: 18,
              child: _FlowerSticker(emoji: '🌼', size: 34, angle: .18),
            ),
            const Positioned(
              bottom: 62,
              left: 24,
              child: _FlowerSticker(emoji: '🌸', size: 38, angle: -.12),
            ),
            const Positioned(
              bottom: 150,
              right: 16,
              child: _FlowerSticker(emoji: '🌴', size: 40, angle: .12),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                      decoration: BoxDecoration(
                        color: palette.cardColor,
                        borderRadius: BorderRadius.circular(32),
                        border: Border.all(color: palette.cardBorder),
                        boxShadow: [
                          BoxShadow(
                            color: palette.cardShadow,
                            blurRadius: 24,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _LoginHeader(palette: palette),
                            const SizedBox(height: 28),
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              style: const TextStyle(color: _navy),
                              decoration: _inputDecoration(
                                labelText: 'メールアドレス',
                                icon: Icons.mail_outline_rounded,
                              ),
                              validator: (v) => (v == null || !v.contains('@'))
                                  ? 'メールアドレスを入力してください'
                                  : null,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _passwordController,
                              style: const TextStyle(color: _navy),
                              obscureText: _obscurePassword,
                              decoration: _inputDecoration(
                                labelText: 'パスワード',
                                icon: Icons.lock_outline_rounded,
                                helperText: '6文字以上',
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? Icons.visibility_off
                                        : Icons.visibility,
                                    color: _navy,
   
                                  ),
                                  tooltip: _obscurePassword ? '表示' : '非表示',
                                  onPressed: () => setState(
                                    () => _obscurePassword = !_obscurePassword,
                                  ),
                                ),
                              ),
                              validator: (v) => (v == null || v.length < 6)
                                  ? 'パスワードは6文字以上で入力してください'
                                  : null,
                            ),
                            // 新規登録時のみ、入力ミス防止のためパスワード確認欄を表示。
                            if (_isSignUp) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirmController,
                                obscureText: _obscurePassword,
                                style: const TextStyle(color: _navy),
                                decoration: _inputDecoration(
                                  labelText: 'パスワード（確認）',
                                  icon: Icons.lock_reset_rounded,
                                ),
                                validator: (v) =>
                                    (v != _passwordController.text)
                                    ? 'パスワードが一致しません'
                                    : null,
                              ),
                            ],
                            const SizedBox(height: 26),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton(
                                style: FilledButton.styleFrom(
                                  backgroundColor: _yellow,
                                  foregroundColor: _navy,
                                  disabledBackgroundColor: _yellow.withValues(
                                    alpha: .45,
                                  ),
                                  disabledForegroundColor: _navy.withValues(
                                    alpha: .55,
                                  ),
                                  minimumSize: const Size.fromHeight(56),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: .4,
                                  ),
                                ),
                                onPressed: isLoading ? null : _submit,
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : Text(_isSignUp ? '新規登録' : 'ログイン'),
                              ),
                            ),
                            TextButton(
                              onPressed: isLoading ? null : _toggleMode,
                              style: TextButton.styleFrom(
                                foregroundColor: _pink,
                                textStyle: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: .1,
                                ),
                              ),
                              child: Text(
                                _isSignUp
                                    ? 'アカウントをお持ちの方はログイン'
                                    : 'アカウントが無い方は新規登録',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 入力欄は常に明るい黄色チップ（ライト/ダーク共通）。カード自体が暗くなっても
  // フォーム部分の可読性を優先する。
  InputDecoration _inputDecoration({
    required String labelText,
    required IconData icon,
    String? helperText,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: labelText,
      helperText: helperText,
      labelStyle: const TextStyle(color: _navy),
      helperStyle: const TextStyle(color: _navy),
      prefixIcon: Icon(icon, color: _navy),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: _yellowLight,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF9FE5E0)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: _yellow, width: 2),
      ),
    );
  }
}

// ライト/ダークそれぞれの装飾カラーセット。
// 入力欄・ボタン・リンクは共通で使えるため対象外（State側の定数を使用）。
class _LoginPalette {
  const _LoginPalette({
    required this.bgGradient,
    required this.cardColor,
    required this.cardBorder,
    required this.cardShadow,
    required this.headerTitleColor,
    required this.headerSubtitleColor,
    required this.sunColor,
    required this.cloudColor,
    required this.waveColor,
    required this.aquaWaveColor,
  });

  final List<Color> bgGradient;
  final Color cardColor;
  final Color cardBorder;
  final Color cardShadow;
  final Color headerTitleColor;
  final Color headerSubtitleColor;
  final Color sunColor;
  final Color cloudColor;
  final Color waveColor;
  final Color aquaWaveColor;

  static const light = _LoginPalette(
    bgGradient: [Color(0xFF7DD8FF), Color(0xFFDDF9FF), Color(0xFF73DCCB)],
    cardColor: Colors.white,
    cardBorder: Color(0xFFFF8A8A),
    cardShadow: Color(0x22000000),
    headerTitleColor: Color(0xFF17213C),
    headerSubtitleColor: Color(0xFF687087),
    sunColor: Color(0xFFFFE27A),
    cloudColor: Color(0xA3FFFFFF),
    waveColor: Color(0xBFFFFFFF),
    aquaWaveColor: Color(0x6671CFC4),
  );

  // 「夜のHanalog」— 太陽は月に、空は紺〜ティールのグラデーションに。
  static const dark = _LoginPalette(
    bgGradient: [Color(0xFF0B1A3A), Color(0xFF14213F), Color(0xFF0F3D3A)],
    cardColor: Color(0xFF1B2338),
    cardBorder: Color(0xFF3A4A6B),
    cardShadow: Color(0x55000000),
    headerTitleColor: Color(0xFFFFF3D6),
    headerSubtitleColor: Color(0xFFAAB2CC),
    sunColor: Color(0xFFF4E9C1),
    cloudColor: Color(0x1FFFFFFF),
    waveColor: Color(0x2EFFFFFF),
    aquaWaveColor: Color(0x4D1F5C55),
  );

  static _LoginPalette of(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return isDark ? dark : light;
  }
}

// ログイン画面上部のブランドヘッダー。アプリ名とひとことを表示する。
class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.palette});

  final _LoginPalette palette;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Container(
          width: 92,
          height: 92,
          decoration: BoxDecoration(
            // ロゴタイルは視認性優先で常に明るいクリーム色のまま。
            color: const Color(0xFFFFF9E6),
            borderRadius: BorderRadius.circular(26),
            boxShadow: const [
              BoxShadow(
                color: Color(0x44FFD21F),
                blurRadius: 12,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Image.asset(
            'assets/images/hanalog_hibiscus_icon.png',
            width: 88,
            height: 88,
            fit: BoxFit.contain,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Hanalog',
          style: theme.textTheme.headlineMedium?.copyWith(
            color: palette.headerTitleColor,
            fontSize: 32,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'みんなの「今」をシェアしよう！',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: palette.headerSubtitleColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _TropicalBackground extends StatelessWidget {
  const _TropicalBackground({required this.palette});

  final _LoginPalette palette;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TropicalBackgroundPainter(palette));
  }
}

class _TropicalBackgroundPainter extends CustomPainter {
  _TropicalBackgroundPainter(this.palette);

  final _LoginPalette palette;

  @override
  void paint(Canvas canvas, Size size) {
    final sunPaint = Paint()..color = palette.sunColor;
    canvas.drawCircle(
      Offset(size.width * .84, size.height * .13),
      42,
      sunPaint,
    );

    final cloudPaint = Paint()..color = palette.cloudColor;
    canvas.drawCircle(
      Offset(size.width * .12, size.height * .16),
      28,
      cloudPaint,
    );
    canvas.drawCircle(
      Offset(size.width * .19, size.height * .14),
      38,
      cloudPaint,
    );
    canvas.drawCircle(
      Offset(size.width * .27, size.height * .17),
      24,
      cloudPaint,
    );

    final wavePaint = Paint()
      ..color = palette.waveColor
      ..style = PaintingStyle.fill;
    final wave = Path()
      ..moveTo(0, size.height * .79)
      ..quadraticBezierTo(
        size.width * .22,
        size.height * .70,
        size.width * .48,
        size.height * .80,
      )
      ..quadraticBezierTo(
        size.width * .75,
        size.height * .90,
        size.width,
        size.height * .77,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(wave, wavePaint);

    final aquaPaint = Paint()..color = palette.aquaWaveColor;
    final aquaWave = Path()
      ..moveTo(0, size.height * .88)
      ..quadraticBezierTo(
        size.width * .3,
        size.height * .79,
        size.width * .58,
        size.height * .89,
      )
      ..quadraticBezierTo(
        size.width * .8,
        size.height * .96,
        size.width,
        size.height * .86,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(aquaWave, aquaPaint);
  }

  @override
  bool shouldRepaint(covariant _TropicalBackgroundPainter oldDelegate) =>
      oldDelegate.palette != palette;
}

class _FlowerSticker extends StatelessWidget {
  const _FlowerSticker({
    required this.emoji,
    required this.size,
    required this.angle,
  });

  final String emoji;
  final double size;
  final double angle;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: angle,
      child: Text(
        emoji,
        style: TextStyle(
          fontSize: size,
          shadows: const [
            Shadow(
              color: Color(0x33000000),
              blurRadius: 4,
              offset: Offset(1, 2),
            ),
          ],
        ),
      ),
    );
  }
}