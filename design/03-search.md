# 03 Search

## 1. 入口

侧边栏顶部右侧搜索图标进入搜索状态。

页面内不显示“搜索”标题，不使用“会话 / 工作区”Tab。

## 2. 未输入时

仅显示：
- 最近会话
- 底部搜索框
- 关闭按钮

“最近会话”是搜索页的辅助内容，不是“最近工作区”概念。

## 3. 输入后

隐藏最近会话，按分组一次展示完整结果：

```text
工作区
...

会话
...

电脑（仅有结果时）
...
```

无结果分组直接隐藏。

## 4. 搜索字段

Workspace：
- 名称
- 目录 basename
- 完整路径

Session：
- Session 名称
- 所属 Workspace 名称

Computer：
- 用户设置的电脑名称
- Worker hostname

不再搜索“Agent 类型 / Shell 类型”，因为 Session 没有类型。

## 5. Session 结果

Session 必须带 Workspace 上下文：

```text
终端 1
CortexTerminal2 · 运行中
```

不能只显示孤立的 Session 名称。

## 6. 视觉

- ChatGPT Mobile Light。
- 底部大圆角搜索 Surface。
- Workspace 图标统一中性色。
- 不堆 Badge，不做多层 Card。
- 输入后实时过滤。
