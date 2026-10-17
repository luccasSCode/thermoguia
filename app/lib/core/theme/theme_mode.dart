import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

enum ThemeSetting {
  system('Do sistema', ThemeMode.system),
  light('Claro', ThemeMode.light),
  dark('Escuro', ThemeMode.dark);

  const ThemeSetting(this.label, this.mode);
  final String label;
  final ThemeMode mode;
}

class ThemeSettingController extends Notifier<ThemeSetting> {
  @override
  ThemeSetting build() {
    final saved = ref.read(localStoreProvider).getString('theme_mode');
    return ThemeSetting.values.firstWhere((s) => s.name == saved, orElse: () => ThemeSetting.system);
  }

  Future<void> set(ThemeSetting s) async {
    state = s;
    await ref.read(localStoreProvider).setString('theme_mode', s.name);
  }
}

final themeSettingProvider = NotifierProvider<ThemeSettingController, ThemeSetting>(ThemeSettingController.new);
