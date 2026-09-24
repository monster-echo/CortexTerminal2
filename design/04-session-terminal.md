# 04 Session Terminal

## 1. 定位

Session 本质是 xterm 终端，不是聊天页面、Agent Timeline 或任务详情页。

## 2. 默认页面

- xterm 占满整个可用页面。
- 不额外包 Card、白色容器或详情区。
- 左上悬浮返回按钮。
- 右上悬浮三点按钮。
- 键盘未弹出时没有底部 Toolbar。

## 3. Keyboard Toolbar

只有系统键盘弹出时显示，用于移动端特殊按键输入：

```text
Ctrl  Esc  Tab  |  /  ↑  ↓  ←  →
```

可按实际需求增加 Home / End / PgUp / PgDn / Alt。

键盘收起后 Toolbar 同步消失。

## 4. 三点菜单

当前只包含：

```text
文件             >
端口转发         >
```

菜单顶部可用弱信息显示当前上下文：

```text
CortexTerminal2
Mac mini
```

不要重新引入完整 AppBar。

## 5. 连接状态

至少支持：
- connecting
- connected
- reconnecting
- disconnected
- worker offline
- ended

正常状态下不显示“重连”按钮。

网络中断时允许在 xterm 上方出现轻量 Overlay：

```text
正在重新连接…
```

自动重连失败后再显示：

```text
连接已断开
[ 重新连接 ]
```

## 6. 返回行为

返回按钮回到进入 Session 前的页面；退出页面不等于结束 Session。

若需要结束 Session，应通过独立明确操作处理，不能把系统返回当成关闭终端。

## 7. Flutter 结构

```text
Stack
├─ Positioned.fill → XtermView
├─ top-left → FloatingBackButton
├─ top-right → FloatingMoreButton
├─ connection overlay（条件显示）
└─ bottom → KeyboardToolbar（仅键盘显示）
```
