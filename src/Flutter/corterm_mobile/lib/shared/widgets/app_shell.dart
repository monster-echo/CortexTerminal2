import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/corterm_theme.dart';
import '../../features/home/home_shell.dart';

/// 顶层壳（design/07 Light App Context）：
/// 「我的」/设置等二级页与新首页共用同一个新侧边栏（CortermSidebar）与视觉 token。
/// settings 保留为枚举值：设置页从「我的」进入，侧边栏不再有独立入口。
enum ShellTab { home, workers, settings, me }

class AppShellScaffold extends ConsumerStatefulWidget {
  const AppShellScaffold({
    super.key,
    required this.tab,
    required this.title,
    required this.body,
    this.actions = const [],
    // 从「我的」等页面压栈进入时为 true：leading 变返回键而不是汉堡按钮。
    this.showBack = false,
  });

  final ShellTab tab;
  final String title;
  final Widget body;
  final List<Widget> actions;
  final bool showBack;

  @override
  ConsumerState<AppShellScaffold> createState() => _AppShellScaffoldState();
}

class _AppShellScaffoldState extends ConsumerState<AppShellScaffold> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    final c = colorsOf(context);
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: c.background,
      drawer: const CortermSidebar(),
      appBar: AppBar(
        backgroundColor: c.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leadingWidth: 48,
        leading: Padding(
          padding: const EdgeInsets.only(left: 4),
          child: widget.showBack
              ? BackButton(color: c.textPrimary, onPressed: () => context.pop())
              : IconButton(
                  icon: Icon(Icons.menu, color: c.textPrimary),
                  onPressed: () => _scaffoldKey.currentState?.openDrawer(),
                ),
        ),
        title: Text(widget.title,
            style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w600,
                color: c.textPrimary)),
        centerTitle: false,
        actions: widget.actions,
      ),
      body: widget.body,
    );
  }
}
