// グループ作成画面。グループ名を入力し、招待コードを自動生成して作成・自動参加する。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../home/home_provider.dart';
import 'group_provider.dart';

class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  final _nameController = TextEditingController();
  bool _submitting = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      _showMessage('グループ名を入力してください');
      return;
    }

    setState(() => _submitting = true);
    try {
      final group = await ref.read(groupServiceProvider).createGroup(name);
      if (!mounted) return;
      ref.invalidate(myGroupsProvider);
      _showMessage('「${group.name}」を作成しました（招待コード: ${group.inviteCode}）');
      context.go('/home');
    } catch (e) {
      if (!mounted) return;
      _showMessage('作成に失敗しました: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('グループ作成')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _nameController,
              enabled: !_submitting,
              decoration: const InputDecoration(
                labelText: 'グループ名',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _create(),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _submitting ? null : _create,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('作成する'),
            ),
          ],
        ),
      ),
    );
  }
}
