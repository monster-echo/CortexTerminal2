import 'package:flutter/material.dart';

/// 右推抽屉控制器：给 AppBar 汉堡按钮和菜单项调用。
class PushDrawerController {
  _PushDrawerShellState? _state;

  bool get isOpen => _state?._isOpen ?? false;

  void open() => _state?._open();
  void close() => _state?._close();
  void toggle() => _state?._toggle();
}

/// 右推抽屉：菜单固定在下层，主内容（含 AppBar）整体右移露出菜单，全程无遮罩。
///
/// Flutter 没有内置该交互——`Scaffold.drawer` / `NavigationDrawer` 都是带 scrim 的
/// 覆盖式。现有第三方包也都套不进本项目的结构（2026-09 在 Flutter 3.47.3 实测）：
/// - flutter_slider_drawer：`appBar` 只接受自己的 `SliderAppBar`，其它 widget 会被
///   静默换成 `SizedBox.shrink()`，CortermAppBar 会消失；
/// - drawerbehavior：菜单槽位在 `SingleChildScrollView` 内（无界高度，侧栏的
///   `Spacer` 直接报错），主内容被额外包进 `Card`，且平移量写死为
///   `(宽度 - elevation - 2)`，304 只能推出 302；
/// - kf_drawer / flutter_zoom_drawer：接管整屏结构与自己的菜单数据模型。
///
/// 所以这里只保留「平移」本身：一个 AnimationController + Transform.translate。
/// 手势判定沿用 Material `DrawerController` 的做法——关闭态只在左边缘起手才允许打开，
/// 打开态任意位置的横向拖动都用于关闭；位移量与时长对齐 ArkTS 侧 ShellScaffold
/// 的 304 / 300ms。
class PushDrawerShell extends StatefulWidget {
  const PushDrawerShell({
    super.key,
    required this.controller,
    required this.menu,
    required this.child,
    this.width = 304,
    this.edgeDragWidth = 24,
    this.duration = const Duration(milliseconds: 300),
  });

  final PushDrawerController controller;

  /// 下层菜单：占满高度，宽 [width]。
  final Widget menu;

  /// 上层内容：通常是一整块 Scaffold，AppBar 会跟着一起右移。
  final Widget child;

  final double width;

  /// 关闭态允许起手开抽屉的左边缘宽度（同 Material drawerEdgeDragWidth 语义）。
  final double edgeDragWidth;

  final Duration duration;

  @override
  State<PushDrawerShell> createState() => _PushDrawerShellState();
}

class _PushDrawerShellState extends State<PushDrawerShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: widget.duration,
  );

  /// 本次横向拖动是否从左边缘起手。
  bool _dragFromEdge = false;

  /// PopScope 需要重建：抽屉开合会改变 canPop。
  bool _canPop = true;

  /// 菜单只在展开/展开中挂载。完全关闭时不构建——与 Material DrawerController 一致，
  /// 避免关闭状态下白白构建整块侧栏（侧栏里有 Provider 订阅与列表）。
  bool _menuMounted = false;

  bool get _isOpen => _slide.value > 0;

  @override
  void initState() {
    super.initState();
    widget.controller._state = this;
    _slide.addListener(_syncFrameState);
  }

  @override
  void didUpdateWidget(PushDrawerShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller._state = null;
      widget.controller._state = this;
    }
  }

  @override
  void dispose() {
    widget.controller._state = null;
    _slide.dispose();
    super.dispose();
  }

  void _syncFrameState() {
    final canPop = !_isOpen;
    final menuMounted = _isOpen || _slide.status == AnimationStatus.forward;
    if (canPop == _canPop && menuMounted == _menuMounted) return;
    setState(() {
      _canPop = canPop;
      _menuMounted = menuMounted;
    });
  }

  void _open() => _slide.animateTo(
    1,
    duration: widget.duration,
    curve: Curves.easeOutCubic,
  );
  void _close() => _slide.animateBack(
    0,
    duration: widget.duration,
    curve: Curves.easeOutCubic,
  );
  void _toggle() => _isOpen ? _close() : _open();

  void _onDragDown(DragDownDetails details) {
    _dragFromEdge = details.globalPosition.dx <= widget.edgeDragWidth;
  }

  /// 关闭态只有从左边缘起手才驱动抽屉；打开态任意位置都可以拖回去。
  /// 内层横向手势组件（首页卡片的 flutter_slidable 等）在手势竞技场里更靠内，
  /// 会先胜出，因此这里的判定不会抢走它们的横滑。
  bool get _dragMovesDrawer => _isOpen || _dragFromEdge;

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragMovesDrawer) return;
    // 内容整体右移 = 打开方向，所以位移取正号。
    _slide.value += details.primaryDelta! / widget.width;
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragMovesDrawer) return;
    if (_slide.value > 0.5) {
      _open();
    } else {
      _close();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // 抽屉展开时先收抽屉，再让系统处理返回（Android 返回键 / 返回手势）。
      canPop: _canPop,
      onPopInvokedWithResult: (didPop, Object? result) {
        if (!didPop) _close();
      },
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: widget.width,
            child: _menuMounted
                ? Semantics(
                    container: true,
                    explicitChildNodes: true,
                    label: MaterialLocalizations.of(context).drawerLabel,
                    child: widget.menu,
                  )
                : const SizedBox.shrink(),
          ),
          AnimatedBuilder(
            animation: _slide,
            builder: (context, child) => Transform.translate(
              offset: Offset(widget.width * _slide.value, 0),
              child: child,
            ),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              // 打开后点内容（右移后残留的那一条）收起；关闭时交给内层控件。
              onTap: () {
                if (_isOpen) _close();
              },
              onHorizontalDragDown: _onDragDown,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}
