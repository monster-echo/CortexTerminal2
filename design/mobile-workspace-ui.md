# Corterm 移动端 Workspace UI 设计规划

> 目标：在 Flutter 移动端中引入 `Worker → Workspace → Session` 的产品模型，同时避免把后端层级直接暴露给用户。整体视觉参考 ChatGPT Mobile Light：轻背景、弱边框、大留白、少量圆角容器、内容优先、克制使用强调色。

## 1. 产品信息架构

底层数据关系保持：

```text
Worker
  └─ Workspace
      └─ Session
```

但移动端 UI 不直接按照三级树导航。用户的主要心智应为：

```text
Workspace
  └─ Session

Workspace 运行在某台电脑（Worker）上
```

### 定义

- **Worker**：一台已配对的远端电脑，是基础设施对象。
- **Workspace**：远端电脑上的一个工作目录，是移动端的一等工作对象。
- **Session**：运行在 Workspace 内的 Shell / Claude Code / Codex 等会话。

## 2. 设计原则

### 2.1 Workspace-first

移动端主要围绕 Workspace 组织内容，而不是先让用户选择 Worker。

用户更容易理解：

> “我要继续 CortexTerminal2”

而不是：

> “我要先进入 Mac mini，再找到某个目录，再进入会话。”

### 2.2 Worker 降级为设备上下文

Worker 不作为首页核心层级，而作为 Workspace 的运行设备信息出现，例如：

```text
CortexTerminal2
Mac mini · 在线
~/Projects/CortexTerminal2
```

完整 Worker 管理放入「电脑」页面。

### 2.3 ChatGPT Mobile Light 视觉语言

不做 Dashboard 风格，不使用大量卡片、边框、彩色标签。

视觉原则：

- 主背景以白色 / 极浅灰为主。
- 大量使用留白建立层级。
- 圆角主要用于搜索、按钮、设置类 Surface，不为所有内容强行加卡片。
- 文字是主视觉，图标仅辅助。
- Workspace 不使用多种颜色进行区分。
- 在线、运行、错误等状态才使用语义色。
- 选中状态使用浅灰背景，不使用大面积品牌蓝。

## 3. 首页结构

首页顶部结构：

```text
☰          [ 工作区 | 电脑 ]          ＋
```

### 3.1 工作区 Tab

首页默认进入「工作区」。

这里不是“最近工作区”，标题只叫：

**工作区**

默认显示最多 5 个 Workspace。

每个 Workspace 使用中性色图标，不使用蓝 / 紫 / 绿 / 黄等不同颜色区分。

示例：

```text
Corterm
连接你的电脑，随时开启高效工作

CortexTerminal2                      ···
工作区 · Mac mini
Claude Code · 运行中

Dancebull                           ···
工作区 · Mac mini
Shell · 1 小时前

...
```

每个 Workspace 最多展示：

- Workspace 名称
- 所属电脑
- 当前最相关的 Session 状态
- 更多菜单

不展示：

- CPU / 内存
- Worker 版本
- IP
- Gateway 状态
- 复杂统计数字

### 3.2 电脑 Tab

首页顶部切换到「电脑」后，展示 Worker 列表：

```text
Mac mini
在线 · 24 ms
3 个工作区

Ubuntu Server
在线 · 47 ms
2 个工作区
```

电脑页负责：

- 查看 Worker 状态
- 新增 / 配对电脑
- 进入 Worker 详情

不承担主要工作入口。

## 4. 侧边栏设计

侧边栏参考 ChatGPT Mobile 的布局方式。

### 4.1 顶部

顶部只有：

```text
Corterm                              🔍
```

规则：

- 顶部没有「新建」按钮。
- 顶部只有搜索入口。
- 搜索用于查找 Workspace 和 Session。

### 4.2 主导航

```text
工作区
电脑
```

仅保留当前移动端核心业务入口，不堆叠大量管理能力。

### 4.3 Workspace 区域

标题：

```text
工作区
```

不是“最近”，也不是“最近工作区”。

默认行为：

1. 最多展示 5 个 Workspace。
2. 默认展开第一个 Workspace。
3. 其他 Workspace 默认折叠。
4. 任意 Workspace 都可以展开 / 收起。
5. 展开后显示该 Workspace 下的 Session。
6. 第 5 个之后使用「更多」入口展示全部 Workspace。

示例：

```text
工作区

⌄  CortexTerminal2
   ● Claude Code · 运行中
   ○ Shell · 空闲

›  Dancebull
›  工作备份
›  前端项目
›  AI 实验室

…  更多
```

### 4.4 Workspace 颜色规则

严禁为每个 Workspace 分配不同颜色。

统一使用：

- 中性色文件夹图标
- 中性色文字
- 选中态浅灰背景
- 展开箭头 / chevron

只有状态使用语义色：

- Online / Running：绿色
- Idle：灰色
- Warning：橙色
- Error / Offline：红色或弱红色

### 4.5 底部固定区域

侧边栏底部：

```text
＋ 新建                                  [用户头像]
```

规则：

- 只有「新建」，没有「新聊」。
- 原本“新聊”的位置改为用户入口。
- 点击用户头像进入账户 / 设置 / 订阅。

## 5. 新建流程

点击「新建」后，不直接创建 Session。

根据上下文打开 Bottom Sheet：

```text
新建

新建会话
新建工作区
连接电脑
```

若当前已有 Workspace 上下文，则「新建会话」为优先操作。

## 6. Worker 配对流程

入口：

```text
电脑 → ＋
```

或者：

```text
新建 → 连接电脑
```

流程：

```text
扫码电脑二维码
    ↓
Worker 配对成功
    ↓
选择远端文件夹
    ↓
创建 Workspace
```

用户界面文案使用「连接电脑」，不优先暴露 Worker 术语。

## 7. 创建 Workspace 流程

扫码成功后：

```text
Mac mini
已连接

选择文件夹
~/Projects/CortexTerminal2
~/Projects/ai-midi-workspace
~/Projects/MV2

Workspace 名称
CortexTerminal2

创建工作区
```

规则：

- Workspace 默认名称取远端目录 basename。
- 用户可以修改名称。
- 必须通过远端目录选择器选择路径，不要求手工输入完整路径。

## 8. Workspace 详情页

Workspace 详情页承载真正的工作内容。

顶部：

```text
CortexTerminal2
Mac mini · ~/Projects/CortexTerminal2
```

内容导航：

```text
会话 | 文件 | 活动
```

### 8.1 会话

展示该 Workspace 下的 Session：

```text
Claude Code
运行中

Shell
空闲

Codex
空闲
```

底部保留：

```text
＋ 新建会话
```

### 8.2 文件

使用现有远程文件能力，浏览当前 Workspace 对应的远端目录。

### 8.3 活动

用于展示 Agent / Session 活动，而不是放在首页。

## 9. Session 创建规则

Workspace 已经定义：

- Worker
- cwd / 目录

因此创建 Session 时不再重复要求选择路径。

新建 Session 只选择执行类型：

```text
Claude Code
Codex
Shell
Custom Command
```

然后直接在当前 Workspace 路径启动。

## 10. 搜索

侧边栏顶部搜索覆盖：

- Workspace 名称
- Session 名称
- Agent 类型
- 电脑名称

搜索结果分组：

```text
工作区
会话
电脑
```

## 11. Light Theme 设计 Token

建议初始 token：

```text
Background           #FFFFFF
Surface              #F5F5F5
Surface Selected     #ECECEC
Text Primary         #111111
Text Secondary       #6F6F6F
Divider              #E7E7E7

Accent               #4A90F8
Success              #34C759
Warning              #FF9F0A
Danger               #FF3B30
```

品牌蓝保持克制，仅用于：

- 链接
- 少量 selected indicator
- CTA
- Logo / 品牌元素

主按钮可以优先采用 ChatGPT 风格的黑底白字，而不是全局使用品牌蓝。

## 12. Flutter 实现建议

建议基于 Flutter Material 3 自定义轻量 Design System，不引入重型 UI 框架。

页面结构：

```text
AppShell
├─ HomePage
│  ├─ WorkspaceTab
│  └─ ComputerTab
├─ AppDrawer
├─ WorkspacePage
├─ SessionPage
├─ RemoteFilesPage
├─ ComputerPage
├─ PairComputerPage
├─ CreateWorkspacePage
└─ AccountPage
```

建议核心组件：

```text
CortermDrawer
WorkspaceListItem
WorkspaceExpandableItem
SessionListItem
ComputerListItem
StatusDot
WorkspaceHeader
RemoteFolderPicker
CreateMenuSheet
UserEntryButton
```

## 13. 交互细节

### 侧边栏

- 使用 Drawer / 自定义侧滑层。
- 保持展开 Workspace 状态。
- 默认第一个 Workspace 展开。
- 展开状态切换不触发页面刷新。

### 触觉反馈

建议：

- 展开 / 收起 Workspace：轻触反馈
- 新建成功：成功反馈
- 配对成功：成功反馈
- 危险操作：警告反馈

### Modal / Bottom Sheet

以下操作使用 Bottom Sheet：

- 新建
- Workspace 更多菜单
- Session 更多菜单
- 选择 Session 类型

不要为这些操作新开完整页面。

## 14. 明确禁止的 UI 反模式

以下设计不采用：

- Worker → Workspace → Session 的三级页面钻取
- 首页 Dashboard 化
- 每个 Workspace 使用不同颜色
- 每个条目都套 Card
- 大量彩色 Badge
- 大面积品牌蓝
- 首页展示 CPU / RAM 图表
- Workspace 再次要求用户选择 cwd
- 使用“最近工作区”作为一级概念
- 侧边栏顶部放新建按钮
- 同时出现“新建”和“新聊”

## 15. 最终用户路径

### 首次使用

```text
打开 App
→ 电脑
→ 连接电脑
→ 扫码
→ 选择远端目录
→ 创建 Workspace
→ 新建 Session
```

### 日常使用

```text
打开 App
→ 首页工作区
→ 进入 Workspace
→ 点击 Session
```

或者：

```text
打开侧边栏
→ 已展开的 Workspace
→ 直接进入 Session
```

## 16. 当前确认版本

本设计当前已确认以下核心决策：

- Flutter 移动端采用 ChatGPT Mobile Light 风格作为视觉参考。
- 使用侧边栏作为主要导航机制。
- Workspace 为移动端核心信息对象。
- Worker 作为「电脑」存在。
- Workspace 默认展示 5 个。
- 默认展开第一个 Workspace。
- 其他 Workspace 可独立展开。
- 「更多」进入全部 Workspace。
- Workspace 统一中性色，不使用多色区分。
- 侧边栏顶部只有搜索。
- 侧边栏底部只有「新建」与用户入口。
- 不使用「新聊」概念。
