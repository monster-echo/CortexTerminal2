import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

Map<ShortcutActivator, Intent> get defaultTerminalShortcuts {
  // 用 if-else 而非 switch：OHOS fork 的 Flutter 给 TargetPlatform 追加了 ohos
  // 枚举值，switch 需穷尽枚举导致两端 SDK 无法同时编译；if-else 无此约束。
  if (defaultTargetPlatform == TargetPlatform.iOS ||
      defaultTargetPlatform == TargetPlatform.macOS) {
    return _defaultAppleShortcuts;
  }
  return _defaultShortcuts;
}

final _defaultShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, control: true, shift: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, control: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, control: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};

final _defaultAppleShortcuts = {
  SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      CopySelectionTextIntent.copy,
  SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
};
