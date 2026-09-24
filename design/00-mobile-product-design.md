# Corterm Mobile Product Design

> 本文档是 Corterm Flutter 移动端设计的唯一总纲。若子文档与本文冲突，以本文为准。

## 1. 核心模型

```text
Worker / 电脑
└─ Workspace / 工作区
   ├─ Session / 终端会话
   └─ PortForward / 端口转发
```

定义：
- Worker：一台通过二维码或配对码建立连接的远端电脑。
- Workspace：某台电脑上的一个远端目录，等于 `Worker + Remote Folder`。
- Session：一个运行在 Workspace 内的 xterm 终端会话。
- PortForward：属于 Workspace 的端口映射规则，不属于某个具体 Session。

重要约束：
- Session 没有 Claude Code / Codex / Shell 类型。
- Claude Code、Codex 等只是用户在终端里运行的程序。
- Workspace 是移动端主要工作对象，Worker 作为设备上下文。

## 2. 页面信息架构

```text
App Shell
├─ 首页
│  ├─ 工作区
│  └─ 电脑
├─ 侧边栏
├─ 搜索
└─ 用户入口

电脑
├─ 电脑列表
└─ 新建电脑 / 扫码配对

工作区
├─ 工作区列表
├─ 工作区详情
├─ 新建工作区
└─ 选择文件夹

Session
└─ 全屏 xterm
   ├─ 返回
   ├─ 更多
   │  ├─ 文件
   │  └─ 端口转发
   └─ Keyboard Toolbar（仅键盘弹出时）
```

## 3. 全局入口规则

- 工作区 Tab 右上角 `+` → 直接进入新建工作区。
- 电脑 Tab 右上角 `+` → 直接进入新建电脑。
- 侧边栏底部「新建」→ 直接进入新建 Session。
- 不使用统一“新建菜单”。
- 不使用“新聊”概念。

## 4. 视觉分区

### Light App Context
用于：
- 首页
- 侧边栏
- 搜索
- 电脑
- Workspace
- 新建流程

视觉参考 ChatGPT Mobile Light：白底、浅灰 Surface、弱边框、大留白、中性色图标、克制强调色。

### Dark Tool Context
用于：
- Session xterm
- Session → 文件
- Session → 端口转发

进入 Session 后切换为完整深色工具环境。

## 5. Workspace 规则

- 首页默认工作区 Tab。
- 侧边栏工作区默认最多显示 5 个。
- 第一个 Workspace 默认展开，其余默认折叠。
- 任意 Workspace 可独立展开/收起。
- 第 5 个以后通过「更多」查看全部工作区。
- Workspace 不使用多种颜色区分；仅状态使用语义色。

## 6. Session 规则

- Session 页面就是全屏 xterm。
- 返回键左上悬浮。
- 三点按钮右上悬浮。
- 键盘未弹出时没有底部 Toolbar。
- 键盘弹出时才显示终端辅助 Toolbar。
- 三点菜单当前只包含：文件、端口转发。
- 三点菜单顶部可显示当前 Workspace / 电脑上下文，但不做 AppBar。

Session 连接状态至少包括：
- connecting
- connected
- reconnecting
- disconnected
- worker offline
- ended

正常状态不显示重连按钮；只有断线失败时显示轻量重连 Overlay。

## 7. 文件与端口转发归属

### 文件
Remote File Browser 归属于 Workspace。入口可以来自：
- Workspace → 文件
- Session → … → 文件

两者打开同一个文件浏览页面，根目录固定为 Workspace Root，不随终端 `cd` 改变。

### 端口转发
PortForward 归属于 Workspace。Session 中的入口只是快捷入口。

## 8. 文档编号

当前设计文档按数字编号维护：

```text
00-mobile-product-design.md      总设计与冲突裁决
01-app-shell-workspace.md        首页 / 侧边栏 / Workspace / 电脑
02-creation-flows.md             新建电脑 / 工作区 / Session / 文件夹选择
03-search.md                     搜索
04-session-terminal.md           xterm Session
05-remote-files.md               文件管理
06-port-forwarding.md            端口转发
07-design-system.md              视觉与组件规则
```

未来新增设计继续使用数字编号，不再创建未编号的 `mobile-*.md` 临时文档。
