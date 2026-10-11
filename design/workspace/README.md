# Workspace 主导的移动端导航

## 设计与实现

参考 `workspace-reference-v1.png`，先生成三屏设计，再实现 ArkUI 页面。

- 默认主页是工作区列表，支持按名称、路径与计算机名称搜索。
- 工作区中集中展示会话、文件与新建会话入口。
- 侧边栏以工作区为中心，箭头展开会话，名称进入工作区，会话进入终端。
- 未分组会话单独收纳，保留原会话恢复、重命名等操作。
- 我的从侧边栏底部头像压栈打开，标题栏与系统返回可回到先前页面。
- 计算机从侧边栏作为二级页面打开，可返回。
- 新建工作区继续复用电脑、文件夹、名称流程。

功能组织参考 [Codex app](https://developers.openai.com/codex/app/features) 的项目与任务组织，以及 [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) 的 workspace/session 模型。本次只实现 CortexTerminal 已有的工作区、终端会话、文件和计算机能力。

## 视觉规格

| 元素 | 规格 |
|---|---|
| 页面左右边距 | 16vp |
| 搜索框 | 44vp 高 |
| 工作区卡片 | 112vp 高，12vp 圆角，1vp 边框 |
| 卡片之间 | 12vp |
| 侧边栏 | 312vp 宽 |
| 主导航行 | 48vp 高 |
| 工作区行 / 展开按钮 | 44vp 高 |
| 工作区会话卡片 | 最低 80vp 高 |
| 固定新建会话按钮 | 48vp 高 |

颜色使用现有 `terminal_*` token；新增 `terminal_scrim` 表达抽屉遮罩。图标 SVG 是可着色的透明轮廓路径，颜色由 theme token 提供。

## 检查记录：2026-10-10

- Mate 60 模拟器，HarmonyOS 6.0.2 API 22，1216×2688，density 3.25。
- 最新 ArkTS / 签名 HAP 构建成功（7 s 705 ms），仍有编译警告。
- `git diff --check` 通过。
- UI dump 实测：边距 52px、搜索框 143px、工作区卡片 364px、卡片间距 39px，均与布局规格换算结果相符。详见 `review/layout-measurements.json`。
- 中英文、深浅主题截图已检查；修复 SVG 着色后填满、异步数量不更新、搜索默认边距和主题遮罩问题。
- 搜索 CortexTerminal2 得到一个匹配；清除恢复六个工作区。
- 未分组独立列表显示三个真实会话。
- 工作区 → 文件 → 返回，工作区 → 我的 → 返回，侧边栏 → 计算机 → 返回主页均通过。
- 侧边栏展开工作区并点击会话，成功进入终端（读取布局确认标题与 xterm Webview）。
- 主页加号可打开新建工作区流程，显示四台真实计算机；未提交新工作区。
- 未执行真实会话新建、删除、重命名、移出等修改操作。本轮没有重跑完整单元测试或 Gateway 测试。

## 截图

| 页面 | 浅色中文 | 深色中文 |
|---|---|---|
| 主页 | `review/home-final-light-zh.jpeg` | `review/home-final-dark-zh.jpeg` |
| 侧边栏展开 | `review/sidebar-expanded-final-light-zh.jpeg` | `review/sidebar-expanded-final-dark-zh.jpeg` |
| 工作区详情 | `review/detail-final-light-zh.jpeg` | `review/detail-final-dark-zh.jpeg` |

另有英文、搜索、新建工作区、未分组、文件以及我的返回导航截图。

2026-10-11 导航修正：工作区详情作为可返回的子页面，左上角显示返回箭头。模拟器确认标题栏返回和系统返回均回到列表，搜索词及筛选结果保留。截图：`review/workspace-returnable.jpeg`、`review/workspace-back-search-retained.jpeg`。此导航修正优先于初版生成图中的菜单按钮。

生成图采用示例数据和示意系统状态栏，实际界面使用真实工作区、原生字体/系统图标和 theme token；未证明与整张生成图逐像素相等。截图复查与布局参数测量已经完成，其他屏幕尺寸和大字体模式尚未覆盖。
