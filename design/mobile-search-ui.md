# Corterm 移动端搜索 UI 设计

> 本文档定义 Corterm Flutter 移动端的搜索体验。该设计延续 `design/mobile-workspace-ui.md` 中的 ChatGPT Mobile Light 视觉方向，并以 Workspace-first 的产品模型为基础。

## 1. 目标

搜索不是一个传统的“独立搜索中心”，而是从侧边栏进入的轻量临时状态。

主要目标：

- 快速找到 Workspace。
- 快速找到 Session。
- 必要时找到电脑（Worker）。
- 搜索结果保持上下文，不让用户只看到孤立的 Session 名称。
- 保持 ChatGPT Mobile Light 的干净、克制、低组件感界面。

## 2. 入口

搜索入口位于侧边栏顶部右侧。

```text
Corterm                              🔍
```

规则：

- 侧边栏顶部只有搜索入口。
- 顶部不放“新建”。
- 点击搜索图标进入搜索状态。

## 3. 页面结构

搜索页不显示“搜索”两个字作为页面标题。

顶部不再放额外标题、Tab 或筛选器。

页面主体保持尽可能空白，底部固定搜索输入区域。

基础结构：

```text

最近会话

Claude Code
CortexTerminal2                         ›

Shell
AI MIDI                                 ›

Codex
MV2                                     ›

Gemini CLI
Geekread                                ›


[ 🔍 搜索工作区、会话或电脑 ]        [ × ]
```

## 4. 未输入关键词时

进入搜索状态但尚未输入关键词时，仅展示：

- 最近会话
- 底部搜索输入框
- 关闭按钮

不展示：

- “搜索”页面标题
- Workspace 列表
- 会话 / 工作区切换 Tab
- 复杂推荐内容
- Dashboard 信息

### 最近会话列表

每个条目使用两行信息：

```text
Claude Code
CortexTerminal2
```

第一行为 Session 名称或 Agent 类型，第二行为所属 Workspace。

点击后直接进入对应 Session。

## 5. 搜索输入区

搜索框固定在页面底部，视觉参考 ChatGPT Mobile 的底部输入 Surface。

结构：

```text
[ 🔍 搜索工作区、会话或电脑 ]    [ × ]
```

规则：

- 搜索框使用浅灰 Surface。
- 使用大圆角。
- 左侧为搜索图标。
- 输入文字后实时搜索。
- 右侧独立圆形 `×` 用于退出搜索状态。
- 输入框自身不需要额外提交按钮。
- 键盘 Search / Enter 可触发确认，但结果应在输入过程中实时更新。

## 6. 搜索结果结构

搜索后，Workspace 和 Session 必须分区展示。

不使用：

```text
[ 会话 | 工作区 ]
```

这样的 Tab 切换。

原因：

- 两个 Tab 会造成同一个搜索词在两个页面之间重复展示信息。
- 用户必须额外切换才能理解完整结果。
- 搜索属于快速定位行为，应一次展示完整结果。

正确结构：

```text
工作区 (N)

CortexTerminal2
~/Projects/CortexTerminal2              ›

AI MIDI
~/Projects/AI-MIDI                       ›


会话 (N)

Claude Code · CortexTerminal2
最近活动 · 2 小时前                      ›

Shell · AI MIDI
最近活动 · 5 小时前                      ›
```

### 分组顺序

默认：

1. 工作区
2. 会话
3. 电脑（仅存在匹配结果时显示）

无结果的分组直接隐藏。

例如没有匹配电脑，则页面只显示：

```text
工作区
...

会话
...
```

不要显示：

```text
电脑 (0)
暂无结果
```

## 7. Workspace 搜索结果

Workspace 条目展示：

- Workspace 名称
- 远端路径
- 右侧 chevron

示例：

```text
▢  CortexTerminal2
   ~/Projects/CortexTerminal2            ›
```

### Workspace 图标

所有 Workspace 使用统一中性色文件夹图标。

禁止：

- 为不同 Workspace 分配蓝、紫、绿、黄、粉等颜色。
- 根据 Workspace 名称生成彩色 Avatar。

Workspace 的身份主要由名称与路径区分，而不是颜色。

## 8. Session 搜索结果

Session 条目必须保留 Workspace 上下文。

不要只显示：

```text
Claude Code
```

应该显示：

```text
Claude Code · CortexTerminal2
最近活动 · 2 小时前
```

或者：

```text
Claude Code
CortexTerminal2 · 运行中
```

允许根据当前数据状态选择第二行信息，但必须能明确知道该 Session 属于哪个 Workspace。

点击后直接进入对应 Session。

## 9. 电脑搜索结果

搜索框允许搜索电脑名称，但电脑不是搜索页的主视觉对象。

只有存在匹配结果时才显示：

```text
电脑 (1)

Mac mini
在线 · 24 ms                           ›
```

点击进入电脑详情。

## 10. 搜索匹配字段

### Workspace

匹配：

- Workspace 名称
- 远端目录 basename
- 完整目录路径

### Session

匹配：

- Session 名称
- Agent 类型
- Shell 类型
- 所属 Workspace 名称

例如：

- Claude Code
- Codex
- Gemini CLI
- Shell

### Computer / Worker

匹配：

- 用户设置的电脑名称
- Worker 主机名

## 11. 搜索行为

建议采用实时搜索。

流程：

```text
进入搜索
↓
显示最近会话
↓
用户输入字符
↓
隐藏最近会话
↓
实时显示分组搜索结果
↓
点击结果进入目标页面
```

当输入框清空时：

```text
搜索结果
↓
恢复最近会话
```

## 12. 空结果

搜索无任何结果时保持克制：

```text
没有找到匹配结果
```

可以附一行弱提示：

```text
尝试搜索工作区名称、会话名称或电脑名称
```

不要加入插画、大卡片或推荐模块。

## 13. 视觉规范

延续 ChatGPT Mobile Light 风格。

建议 token：

```text
Background           #FFFFFF
Surface              #F5F5F5
Surface Selected     #ECECEC
Text Primary         #111111
Text Secondary       #6F6F6F
Divider              #E7E7E7
Success              #34C759
Danger               #FF3B30
```

### 搜索页禁止使用

- 大面积品牌蓝
- 彩色 Workspace 图标
- 多层 Card
- 搜索结果 Badge 堆叠
- 顶部大标题“搜索”
- 会话 / 工作区 Tab
- 同一结果在多个 Tab 中重复出现

## 14. Flutter 组件建议

建议页面：

```text
SearchPage
├─ SearchResultBody
│  ├─ RecentSessionSection
│  ├─ WorkspaceSearchSection
│  ├─ SessionSearchSection
│  └─ ComputerSearchSection
└─ BottomSearchBar
```

建议组件：

```text
BottomSearchBar
SearchWorkspaceItem
SearchSessionItem
SearchComputerItem
RecentSessionItem
SearchSectionHeader
```

状态模型：

```text
SearchState
├─ query
├─ workspaces
├─ sessions
├─ computers
├─ recentSessions
└─ isSearching
```

建议行为：

```text
query.isEmpty
→ show recentSessions

query.isNotEmpty
→ show grouped results
```

## 15. 动效与交互

- 进入搜索页后输入框自动获得焦点，并弹出键盘。
- 搜索结果刷新使用轻微淡入，不使用明显位移动画。
- 点击结果使用标准 Flutter / 平台触觉反馈。
- 点击 `×` 关闭搜索并回到侧边栏。
- 不做复杂 Hero 动画。

## 16. 当前确认规则

当前搜索设计确认如下：

- 搜索从侧边栏顶部进入。
- 页面内不显示“搜索”标题。
- 搜索框固定在底部。
- 未输入关键词时显示最近会话。
- 输入关键词后隐藏最近会话，展示搜索结果。
- Workspace 与 Session 分区展示。
- 不使用“会话 / 工作区”两个 Tab。
- 不让两个标签页展示重复或相同的信息。
- Workspace 结果显示名称 + 路径。
- Session 结果必须显示所属 Workspace 上下文。
- 电脑结果仅在匹配时出现。
- Workspace 图标统一使用中性色，不使用多色区分。
- 整体视觉继续遵循 ChatGPT Mobile Light：白底、浅灰 Surface、弱分割、内容优先。
