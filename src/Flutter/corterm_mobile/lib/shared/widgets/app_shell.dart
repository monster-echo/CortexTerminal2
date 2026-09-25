import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/corterm_theme.dart';

/// 二级页壳（design/07 Light App Context）：
/// 「我的」/设置等压栈页面共用的页面骨架：左上角固定返回键（context.pop）。
/// 侧边栏（CortermSidebar）只属于首页 HomeShell，二级页不挂 Drawer。
enum ShellTab { home, workers, settings, me }

class AppShellScaffold extends StatelessWidget {
  const AppShellScaffold({
    super.key,
    required this.tab,
    required this.title,
    required this.body,
    this.actions = const [],
  });

  final ShellTab tab;
  final String title;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Scaffold(
      backgroundColor: c.background,
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 48,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: BackButton(color: c.textPrimary, onPressed: () => context.pop()),
        ),
        title: Text(title,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.textPrimary)),
        centerTitle: false,
        actions: actions,
      ),
      body: body,
    );
  }
}
