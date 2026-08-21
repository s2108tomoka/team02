// プロフィール画面。usersテーブルの表示名を取得・編集・保存する。

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/supabase_client.dart';
import 'auth_provider.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      final name = await fetchProfileName(user.id);
      if (!mounted) return;
      _nameController.text = name ?? '';
    } catch (_) {
      if (!mounted) return;
      _showMessage('プロフィールの取得に失敗しました。');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final user = supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await updateProfileName(
        userId: user.id,
        name: _nameController.text.trim(),
      );
      if (!mounted) return;
      _showMessage('プロフィールを更新しました。');
      context.pop();
    } catch (_) {
      if (!mounted) return;
      _showMessage('保存に失敗しました。もう一度お試しください。');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('プロフィール')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : Form(
                    key: _formKey,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                          child: Icon(
                            Icons.person_rounded,
                            size: 52,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          'プロフィールを編集',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'みんなに表示される名前を変更できます',
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 28),
                        TextFormField(
                          controller: _nameController,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: '表示名',
                            prefixIcon: Icon(Icons.badge_outlined),
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            final name = value?.trim() ?? '';
                            if (name.isEmpty) return '表示名を入力してください';
                            if (name.length > 30) return '表示名は30文字以内で入力してください';
                            return null;
                          },
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _isSaving ? null : _save,
                            child: _isSaving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('保存する'),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
