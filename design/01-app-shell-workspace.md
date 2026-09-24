# 01 App Shell / Workspace / Computer

## 1. 首页

顶部：

```text
☰          [ 工作区 | 电脑 ]          +
```

规则：
- 默认进入「工作区」。
- 工作区 Tab 的 `+` 直接进入新建工作区。
- 电脑 Tab 的 `+` 直接进入新建电脑。

## 2. 工作区首页

只叫「工作区」，不使用“最近工作区”。

每个条目展示：
- Workspace 名称
- 所属电脑
- 会话数量或最近活动
- 轻量更多入口（如需要）

不展示 CPU/RAM、IP、Worker 版本、Gateway 统计。

Workspace 图标统一使用中性色，不按项目分配多种颜色。

## 3. 电脑首页

展示已配对 Worker：

```text
Mac mini
在线 · 24 ms
3 个工作区
```

电脑页用于：
- 查看设备状态
- 新增电脑
- 进入电脑详情

它不是主要工作入口。

## 4. 侧边栏

顶部：

```text
Corterm                              🔍
```

顶部只有搜索，不放新建。

工作区区域：
- 默认最多显示 5 个。
- 默认展开第一个。
- 其他默认折叠。
- 任意 Workspace 可展开/收起。
- 展开后显示 Session。
- 第 5 个后显示「更多」。

底部固定：

```text
+ 新建                              [用户头像]
```

- 「新建」直接进入新建 Session。
- 用户头像进入账户 / 设置 / 订阅。

## 5. Workspace 详情

Workspace 是：`Worker + Remote Folder`。

详情页建议：
- Workspace 名称
- 电脑与路径作为次级信息
- Session 列表
- 文件入口
- 新建 Session

文件入口与 Session 三点中的“文件”共用同一个 RemoteFilesPage。

## 6. Session 列表

Session 是终端会话，不展示 Agent 类型。

条目建议：

```text
开发终端
运行中 · 12 分钟
```

若用户未命名，可使用系统生成名称，例如“终端 1 / 终端 2”。

## 7. 禁止

- 不把 Worker → Workspace → Session 做成强制三级钻取。
- 不做首页 Dashboard。
- 不给 Workspace 多色标签。
- 不同时出现“新建”和“新聊”。
