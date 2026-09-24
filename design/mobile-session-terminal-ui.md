# Corterm 移动端 Session / Terminal / 文件 / 端口转发设计

> 本文档定义 Corterm Flutter 移动端中 Session 页面及其衍生能力：**全屏 xterm 终端、悬浮返回、悬浮更多菜单、文件浏览、端口转发**。本文档延续 `design/mobile-workspace-ui.md` 与 `design/mobile-creation-flows.md` 的整体产品结构。

## 1. Session 页面定位

Corterm 的 Session 本质是 **终端会话**，不是聊天页面、Agent Timeline、任务详情页或 Dashboard。

Session 页面核心原则：

- xterm 占满整个可用页面。
- 终端内容优先，外围 UI 尽量消失。
- 不展示 Workspace 卡片、电脑卡片、路径卡片等额外信息区块。
- 不在终端下方常驻“重连 / 键盘 / 复制 / 断开”等操作栏。
- 返回按钮与更多按钮使用悬浮控件。
- Toolbar 仅在系统键盘弹出时出现。

## 2. Session 默认页面

默认状态：

```text
┌─────────────────────────────────┐
│  状态栏                         │
│                                 │
│  [ ← ]                    [ … ] │
│                                 │
│  xterm                          │
│  xterm                          │
│  xterm                          │
│  xterm                          │
│                                 │
│                                 │
│                                 │
└─────────────────────────────────┘
```

### 2.1 xterm

- 从状态栏下方延伸到屏幕底部。
- 黑色终端背景与 Session 自身终端主题保持一致。
- 不额外包 Card、圆角容器或边框。
- 支持滚动、选择、复制、粘贴、输入、光标与 ANSI 色彩。

### 2.2 返回按钮

位置：左上悬浮。

行为：

- 点击返回上一层 Workspace / Session 列表。
- 使用半透明深色圆形 Surface。
- 必须悬浮在 xterm 上方，不占用单独 AppBar 高度。

### 2.3 更多按钮

位置：右上悬浮。

结构：

```text
[ … ]
```

点击后弹出轻量菜单：

```text
文件                 ›
端口转发             ›
```

当前阶段菜单只包含这两个核心功能。

## 3. Toolbar 规则

Toolbar 不常驻。

### 3.1 键盘未弹出

页面只显示：

- xterm
- 悬浮返回按钮
- 悬浮更多按钮

不显示：

- 重连
- 键盘按钮
- 复制按钮
- 断开按钮
- 底部操作栏

### 3.2 键盘弹出

系统键盘出现时，在键盘上方显示终端 Toolbar。

Toolbar 只负责移动端终端输入辅助，例如：

```text
Ctrl   Esc   Tab   |   /   ↑   ↓   ←   →
```

可以根据终端实际使用需求继续补充：

- Home
- End
- PgUp
- PgDn
- Alt

Toolbar 的目的不是承载 Session 管理操作，而是提升 xterm 在移动端输入特殊按键时的效率。

### 3.3 键盘关闭

- Toolbar 与键盘一起消失。
- Session 恢复完全沉浸式终端。

## 4. 更多菜单

点击右上角悬浮 `…` 后，在按钮附近弹出 Menu / Popover。

结构：

```text
┌────────────────────┐
│  📁 文件          › │
│  ⇄ 端口转发      › │
└────────────────────┘
```

规则：

- 不使用全屏中间 Modal。
- 不用大型 Bottom Sheet 承载只有两个操作的菜单。
- 菜单视觉采用深色半透明 Surface，与终端背景协调。
- 点击菜单外部关闭。

## 5. 文件功能

### 5.1 入口

```text
Session → … → 文件
```

进入独立“文件”页面。

### 5.2 页面定位

文件页是当前 Session / Workspace 对应远端目录的文件管理器。

默认打开位置：

- 优先进入当前 Workspace 根目录。
- 若 Session 没有 Workspace，则进入当前终端工作目录或用户 Home。

### 5.3 页面结构

```text
文件

[电脑 / 当前路径]
Mac mini  ›  ~/Projects/CortexTerminal2

📁 lib                              ›
📁 packages                         ›
📁 docs                             ›
📄 pubspec.yaml                    …
📄 README.md                       …
📄 .gitignore                      …
```

### 5.4 文件夹

文件夹条目：

- 文件夹图标
- 名称
- 可选修改时间
- 右侧 chevron

点击进入下一层目录。

### 5.5 文件

文件条目：

- 文件图标
- 文件名
- 文件大小 / 修改时间
- 右侧 `…`

点击文件：

- 文本类文件可进入预览。
- 不适合预览的文件进入文件操作菜单。

### 5.6 文件操作

文件 `…` 菜单可包含：

```text
下载
重命名
删除
```

根据已有实现能力可继续增加：

```text
复制路径
移动
复制
```

### 5.7 新建 / 上传

文件页面允许：

- 上传文件
- 新建文件夹
- 新建文本文件（若实现支持）

不要求底部永久同时放三个大按钮。

推荐：

- 右上角 `+`
- 点击后弹出菜单：

```text
上传文件
新建文件夹
新建文件
```

保持文件页面干净。

### 5.8 下载

下载应由具体文件触发，不在没有选择文件时展示一个无意义的全局“下载”按钮。

## 6. 端口转发

### 6.1 入口

```text
Session → … → 端口转发
```

进入独立“端口转发”页面。

### 6.2 页面目标

用于管理当前 Worker / Session 上的端口映射，使手机或其他设备可以访问远端开发服务。

典型场景：

- Web Dev Server
- Vite / Next.js
- API Server
- PostgreSQL
- Redis
- 自定义开发端口

## 7. 端口转发页面

页面结构：

```text
端口转发                                  +

通过端口转发访问远端开发服务。

8080 → 127.0.0.1:8080             [ ON ]
本地 8080 · 远端 8080                 …

3000 → 127.0.0.1:3000             [ ON ]
本地 3000 · 远端 3000                 …

5432 → 127.0.0.1:5432             [ OFF ]
本地 5432 · 远端 5432                 …
```

### 7.1 规则条目

每条端口转发显示：

- 本地端口
- 远端 Host / Port
- 当前状态
- 开关
- `…` 更多操作

推荐主信息：

```text
3000 → 127.0.0.1:3000
```

次信息：

```text
本地 3000 · 远端 3000
```

### 7.2 状态

仅状态使用语义色：

- Running / Enabled：绿色
- Stopped / Disabled：灰色
- Error：红色

不为不同端口分配不同彩色主题。

### 7.3 开关

- Switch 控制该条转发的启动 / 停止。
- 开关切换需有轻触觉反馈。
- 启动失败时使用 Toast / Inline Error，不弹复杂 Alert。

### 7.4 更多操作

点击规则右侧 `…`：

```text
编辑
复制地址
删除
```

删除为危险操作。

## 8. 新建端口转发

入口：

```text
端口转发 → 右上角 +
```

进入独立创建页或轻量 Bottom Sheet。

推荐字段：

```text
新建端口转发

名称（可选）
Web Server

本地端口
8080

远端地址
127.0.0.1

远端端口
8080

[ 创建并启动 ]
```

### 8.1 默认值

- 远端地址默认：`127.0.0.1`
- 如果用户只输入一个远端端口，可以默认将本地端口填为同值。

例如：

```text
远端 3000
→ 本地默认 3000
```

减少输入成本。

## 9. 页面返回关系

```text
Session (xterm)
   ├─ … → 文件
   │       └─ 返回 → Session
   │
   └─ … → 端口转发
           └─ 返回 → Session
```

文件与端口转发属于 Session 的辅助能力，但都是独立页面。

## 10. 视觉规范

Session 相关页面分为两种视觉状态：

### 10.1 Session Terminal

- 深黑背景
- xterm 自身 ANSI 色彩
- 悬浮按钮使用半透明深灰 Surface
- 最大化终端空间
- 不引入 ChatGPT Light 白底容器

### 10.2 文件 / 端口转发

文件和端口转发页面可以继续沿用深色工具界面：

```text
Background       #0B0D0F
Surface          #171A1F
Surface Elevated #20242A
Text Primary     #F5F5F5
Text Secondary   #9CA3AF
Divider          #2B3037
Success          #34C759
Danger           #FF453A
Accent           #3B82F6
```

Accent 蓝保持克制，只用于：

- 当前激活操作
- Switch / selected
- 可交互重点

## 11. Flutter 实现建议

页面结构：

```text
SessionTerminalPage
├─ XtermView
├─ FloatingBackButton
├─ FloatingMoreButton
└─ TerminalKeyboardToolbar (keyboard visible only)

SessionMoreMenu
├─ Files
└─ PortForwarding

RemoteFilesPage
├─ PathHeader
├─ FolderList
├─ FileList
└─ CreateFileMenu

PortForwardingPage
├─ ForwardRuleList
├─ ForwardRuleItem
└─ AddForwardRuleButton
```

### 11.1 Session Terminal

建议使用 `Stack`：

```text
Stack
├─ Positioned.fill → XtermView
├─ Positioned(top,left) → Back
├─ Positioned(top,right) → More
└─ Positioned(bottom) → KeyboardToolbar (conditional)
```

关键点：

- xterm 作为底层全屏内容。
- Back / More 作为 Overlay。
- Toolbar 由键盘可见状态驱动。

## 12. 明确禁止的设计

Session 页面禁止：

- 把 Session 做成聊天页面
- 展示 Agent Timeline 卡片流
- 在顶部常驻 Workspace / Worker / Path 三行详情卡片
- xterm 只占页面中间的一小块
- 底部常驻重连 / 键盘 / 复制 / 断开四按钮
- 为 xterm 添加额外白色外框或 Card
- 键盘未弹出时展示 Terminal Toolbar

文件页面禁止：

- 用复杂桌面文件树直接塞进手机
- 每个文件都做大 Card
- 全局常驻无上下文的“下载”按钮

端口转发页面禁止：

- 首页式 Dashboard
- 图表化展示
- 每条规则使用不同颜色
- 把配置项全部塞到列表条目中直接编辑

## 13. 当前确认版本

当前版本确认：

- Session 就是 xterm 终端。
- xterm 全屏。
- 返回按钮悬浮。
- 三点按钮悬浮。
- 页面底部没有重连、键盘、复制、断开常驻按钮。
- Terminal Toolbar 只有在键盘弹出时出现。
- 三点菜单当前包含：文件、端口转发。
- 文件是独立页面。
- 文件页浏览当前 Workspace / Session 对应远端目录。
- 端口转发是独立页面。
- 端口转发支持查看、开启/关闭、新建、编辑、删除规则。
