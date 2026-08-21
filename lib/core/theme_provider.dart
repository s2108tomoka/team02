// アプリ全体のダークモード状態を管理するプロバイダ。
// home_screen.dartの「ダークモードに切り替え」メニューから更新される。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/legacy.dart'; // StateProvider等の旧来型APIはここから

// 既定はシステム設定に追従（端末側がダークならダークで起動）。
final themeModeProvider = StateProvider<ThemeMode>((ref) => ThemeMode.system);