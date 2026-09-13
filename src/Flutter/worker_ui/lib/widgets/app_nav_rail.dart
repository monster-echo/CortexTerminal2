import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// NavigationRail 的 shadcn 替代：竖排图标+文字导航条。
///
/// 有意不用 ShadTabs：ShadTabs 会保活非激活 tab（Offstage），而各功能页
/// 依赖 dispose 停掉轮询/Timer（session detail 的 2s 拉取等），这里的
/// index 切换语义 = 旧 NavigationRail，非激活页直接销毁。
class AppNavItem {
  const AppNavItem(this.icon, this.label);

  final IconData icon;
  final String label;
}

class AppNavRail extends StatelessWidget {
  const AppNavRail({
    super.key,
    required this.items,
    required this.index,
    required this.onSelect,
  });

  final List<AppNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = ShadTheme.of(context).colorScheme;
    return SizedBox(
      width: 88,
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect(i),
                child: Container(
                  height: 56,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: i == index ? scheme.accent : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        items[i].icon,
                        size: 20,
                        color: i == index ? scheme.foreground : scheme.mutedForeground,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 11,
                          color: i == index ? scheme.foreground : scheme.mutedForeground,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
