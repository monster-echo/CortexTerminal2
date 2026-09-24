# 07 Mobile Design System

## 1. 目标

Corterm 移动端以 ChatGPT Mobile Light 的克制感为主，终端工具区切换为 Dark Tool Context。

## 2. Light Tokens

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

规则：
- 主按钮优先黑底白字。
- 品牌蓝保持克制。
- Workspace 不使用多色区分。
- 只有状态使用语义色。

## 3. Dark Tool Tokens

```text
Background           #0B0D0F
Surface              #171A1F
Surface Elevated     #20242A
Text Primary         #F5F5F5
Text Secondary       #9CA3AF
Divider              #2B3037
Accent               #3B82F6
Success              #34C759
Danger               #FF453A
```

## 4. 组件原则

- 菜单就是 Menu / Popover。
- Modal 只在真正需要阻塞确认时使用。
- Toast 用于轻量结果反馈。
- 危险操作需要明确确认或平台标准交互。
- 按钮保持平台可点击尺寸。
- 不用自造控件替代标准交互语义。

## 5. Card / Surface

避免“所有内容都是卡片”。

优先用：
- 留白
- 字体层级
- 轻分割线
- 少量浅灰 Surface

大圆角主要用于：
- 搜索框
- 输入区域
- 设置类 grouped surface
- 主要按钮

## 6. 图标

- 统一线性、中性色图标。
- Workspace / Folder 不按项目染色。
- 状态颜色只表达状态，不表达身份。

## 7. 动效与触觉

- 页面转场保持平台自然节奏。
- 展开/收起使用轻微动画。
- Workspace 展开、Switch、创建成功可使用轻触觉反馈。
- 不使用炫技 Hero 动画。

## 8. 设计图规则

- 一个功能一个设计图。
- 保持真实移动端页面比例。
- 不把多个功能拼到一张总图作为最终设计稿。
- 总体流程用文档/流程图表达，页面视觉稿单页输出。
