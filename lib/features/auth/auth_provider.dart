// 認証状態を管理するProvider群。
// Supabase Authのセッション監視・メール認証・プロフィール登録判定を担当する。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_client.dart';

// Supabase Authのセッション変化を流すStream。ログイン/ログアウトを検知する。
final authStateProvider = StreamProvider<AuthState>((ref) {
  return supabase.auth.onAuthStateChange;
});

// 現在ログイン中のユーザー。未ログインならnull。
final currentUserProvider = Provider<User?>((ref) {
  ref.watch(authStateProvider);
  return supabase.auth.currentUser;
});

// 認証操作（ログイン・新規登録・ログアウト）を担当するコントローラ。
// 処理中・エラー状態を AsyncValue で表現し、画面側でローディング/エラー表示に使う。
class AuthController extends AsyncNotifier<void> {
  @override
  FutureOr<void> build() {}

  Future<void> signInWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.signInWithPassword(email: email, password: password);
    });
  }

  Future<void> signUpWithEmail(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await supabase.auth.signUp(email: email, password: password);
    });
  }

  Future<void> signOut() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => supabase.auth.signOut());
  }
}

final authControllerProvider =
    AsyncNotifierProvider<AuthController, void>(AuthController.new);

// 自分のプロフィールが users テーブルに登録済みか確認する。
Future<bool> hasProfile(String userId) async {
  final row =
      await supabase.from('users').select('id').eq('id', userId).maybeSingle();
  return row != null;
}

// プロフィール（名前）を users テーブルに登録する。id は Auth のユーザーID。
Future<void> createProfile({
  required String userId,
  required String name,
}) async {
  await supabase.from('users').insert({'id': userId, 'name': name});
}

// 保存済みのプロフィール名を取得する。
Future<String?> fetchProfileName(String userId) async {
  final row = await supabase
      .from('users')
      .select('name')
      .eq('id', userId)
      .maybeSingle();
  return row?['name'] as String?;
}

// プロフィール名を更新する。
Future<void> updateProfileName({
  required String userId,
  required String name,
}) async {
  await supabase.from('users').update({'name': name}).eq('id', userId);
}
