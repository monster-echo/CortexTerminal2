# CortexTerminal2

## 编码原则

- **禁止 fallback / workaround**：不要为异常情况写静默降级、空值兜底、try-catch 吞错误。遇到异常直接抛出，让上层（UI / 调用方）决定如何处理。错误应该在界面上明确展示给用户，而不是被隐藏。
- **最精简逻辑**：该是什么就是什么。不要为了"安全"加多余的 if-else、默认值回退、空操作。如果逻辑上不可能为空，就不要写空值检查。
- **异常即信号**：throw / reject 是正常的控制流。UI 层捕获异常后展示错误信息（error banner / toast），让用户知道发生了什么，而不是假装一切正常。
- **不要问"要不要继续"**：如果任务明确、计划已审批，就一口气做完所有步骤，不要中途停下来问用户是否继续。

## HarmonyOS 设计规范

### 对比度达标线（华为应用市场审核要求）

参考 [华为官方论坛](https://developer.huawei.com/consumer/cn/forum/topic/0204198799066197038)，华为区分对待：

- **正文文字**（≤18sp 的描述/次要文字/链接等）≥ **4.5:1**
- **按钮文字**（按钮上的文字）≥ **3:1**（非 4.5:1）
- 大文字（≥18sp）/图标/可交互元素边框 ≥ **3:1**
- 深色 + 浅色双模式必查

> 关键：按钮蓝用 Twitter hover 色 `#1a8cd8`（白字 3.63:1，超 3:1 线 0.63），浅色链接/次要文字用更深的 `#0a6fc2`（4.74:1，满足正文 4.5:1）——per-token 差异化兼顾品牌识别与合规。

### 颜色系统（Dark Theme · 深色）

| Token | 色值 | 用途 |
|-------|------|------|
| `terminal_surface` | `#0f1419` | 页面主背景 |
| `terminal_surface_container` | `#1a1f2e` | 卡片/表单容器背景 |
| `terminal_surface_container_high` | `#232a3b` | 输入框背景 |
| `terminal_surface_container_highest` | `#2d3548` | 对话框背景 |
| `terminal_primary` | `#e7e9ea` | 主文字/高强调内容 |
| `terminal_secondary` | `#7cacf8` | 次要文字/链接 |
| `terminal_secondary_container` | `#1a8cd8` | 主操作按钮背景（Twitter hover） |
| `terminal_tertiary` | `#00ba7c` | 成功/在线状态 |
| `terminal_error` | `#ff5c5c` | 错误/失败状态 |
| `terminal_on_surface` | `#e7e9ea` | 表面上的文字 |
| `terminal_on_surface_variant` | `#9aa4b0` | 次要/提示文字 |
| `terminal_on_secondary_container` | `#ffffff` | 按钮上的文字 |
| `terminal_outline` | `#6b7785` | 边框/图标/分割线 |
| `terminal_outline_variant` | `#2f3336` | 弱边框/装饰分割线 |

### 颜色系统（Light Theme · 浅色）

| Token | 色值 | 用途 |
|-------|------|------|
| `terminal_surface` | `#f5f5f5` | 页面主背景 |
| `terminal_surface_container` | `#ffffff` | 卡片/表单容器背景 |
| `terminal_surface_container_high` | `#f0f0f0` | 输入框背景 |
| `terminal_surface_container_highest` | `#e8e8e8` | 对话框背景 |
| `terminal_primary` | `#1a1a1a` | 主文字/高强调内容 |
| `terminal_secondary` | `#0a6fc2` | 次要文字/链接（正文，4.74:1） |
| `terminal_secondary_container` | `#1a8cd8` | 主操作按钮背景（Twitter hover） |
| `terminal_tertiary` | `#00824f` | 成功/在线状态 |
| `terminal_error` | `#c81823` | 错误/失败状态 |
| `terminal_on_surface` | `#1a1a1a` | 表面上的文字 |
| `terminal_on_surface_variant` | `#536471` | 次要/提示文字 |
| `terminal_on_secondary_container` | `#ffffff` | 按钮上的文字 |
| `terminal_outline` | `#7a8590` | 边框/图标/分割线 |
| `terminal_outline_variant` | `#e0e0e0` | 弱边框/装饰分割线 |

资源引用方式：`$r('app.color.terminal_surface')`

### 间距系统

| Token | 值 | 用途 |
|-------|----|------|
| `unit` | 4dp | 基础网格单位 |
| `sm` | 8dp | 小间距（元素内部） |
| `md` | 16dp | 中间距（元素之间） |
| `lg` | 24dp | 大间距（区域之间） |
| `edgeMargin` | 16dp | 页面两侧边距 |
| `touchTarget` | 44dp | 最小点击区域 |

### 圆角

| 场景 | 值 |
|------|----|
| 输入框 | 8dp |
| 主按钮 | 24dp（全圆角胶囊） |
| 卡片/表单容器 | 12dp |
| App 图标 | 24dp |
| 小按钮 | 8dp |
| 列表项 | 10dp |

### 字体

| 场景 | 大小 | 字重 |
|------|------|------|
| App 名称 | 28fp | Bold |
| 页面标题 | 20fp | Bold |
| 区域标题 | 18fp | Bold |
| 正文 | 16fp | Normal |
| 标签/说明 | 14fp | Normal |
| 辅助文字 | 13fp | Normal |
| 小字/说明 | 12fp | Normal |
| 极小/时间戳 | 11fp | Normal |

### 组件规范

#### 输入框
- 高度：48dp
- 背景：`terminal_surface_container_high`
- 圆角：8dp
- 文字颜色：`terminal_primary`
- 占位符颜色：`terminal_on_surface_variant`
- 标签：14fp，`terminal_on_surface_variant`，底部间距 8dp
- 输入框间距（垂直）：16dp

#### 主操作按钮
- 高度：48dp
- 背景：`terminal_secondary_container`（`#1a8cd8`，深+浅一致）
- 文字：16fp Medium，`terminal_on_secondary_container`（`#ffffff`，对比度 3.63:1 ≥ 按钮文字 3:1）
- 圆角：24dp（胶囊形）
- 宽度：100%（受 maxWidth 400dp 约束）
- 禁用状态：opacity 0.5

#### 次要操作按钮
- 高度：48dp
- 背景：透明
- 边框：1dp `terminal_outline_variant`
- 文字：14fp Medium，`terminal_primary`
- 圆角：8dp

#### 错误提示条
- 图标：`terminal_error`
- 文字：14fp Medium，`terminal_error`
- 间距：顶部 16dp

#### 分割线
- 颜色：`terminal_outline_variant`
- 间距：左右 16dp，上下 10dp

### 布局规范

- 页面内容区左右 padding：24dp
- 区域之间垂直间距：24-48dp
- 元素之间垂直间距：8-16dp
- 对齐方式：居中或左对齐（表单）

## ArkTS 编译约束（踩坑记录）

ArkTS 是 TypeScript 的严格子集，以下标准 TS/JS 写法**会直接编译报错**：

### 禁止的语法

| 写法 | 报错码 | 正确做法 |
|------|--------|----------|
| `export const X = { ... } as const` | `arkts-no-as-const` | 用 `class X { static readonly A: string = '...' }` |
| `{ key: value }` 无类型对象字面量 | `arkts-no-untyped-obj-literals` | 声明类型：`const body: Record<string, string> = { key: value }` |
| `Record<string, Object> = { ... }` | 同上 | 用 `Record<string, string>` 代替（值都是 primitive） |
| `const [k, v] of Object.entries(obj)` | `arkts-no-destruct-decls` | 用 `Object.keys(obj)` + 索引访问 |
| `throw e`（e 是 catch 的任意类型） | `arkts-limited-throw` | `throw new Error((e as Error).message)` |
| `for ... of` 在某些场景 | 视情况 | 用 `for (let i = 0; i < arr.length; i++)` |

### 类型转换陷阱

- `Record<string, Object>` 的属性值类型是 `Object`，不能直接赋给 `string`。必须 `(obj['key'] as string)` 显式转换
- `AppStorage.get<string>('key')` 返回 `string | undefined`，`|| ''` 后结果类型可能还是 `Object | string`，需要确保上下文类型收窄

### 创建新 HAR 模块的完整清单

新建一个 feature HAR 模块时，以下文件**全部缺一不可**，否则构建失败：

1. `oh-package.json5` — 包名、依赖
2. `build-profile.json5` — 构建配置
3. `hvigorfile.ts` — 内容固定：`import { harTasks } from '@ohos/hvigor-ohos-plugin'; export default { system: harTasks, plugins:[] }`
4. `src/main/module.json5` — **注意扩展名是 `.json5` 不是 `.json`**
5. `src/main/ets/Index.ets` — 模块导出入口
6. 根目录 `build-profile.json5` 的 `modules` 数组中注册模块
7. 使用该模块的 `oh-package.json5`（如 entry）中添加依赖

### 循环依赖陷阱

`common/core` 是所有 feature 的公共依赖，**绝对不能反向依赖任何 feature**。
- `core` 中的类型如果要引用 feature 中定义的接口，要在 core 中重新定义一个同名接口
- 例：`AuthState` 需要 `UserInfo` 的结构，不能从 `@rwecho/auth` import，要在 core 中定义 `StoredUserInfo`

### 构建错误排查顺序

遇到编译错误时，优先检查：
1. `arkts-no-*` 错误 → 查上表替换语法
2. `Cannot find module '@rwecho/xxx'` → 检查新模块是否缺 `hvigorfile.ts` 或 `module.json5` 扩展名不对
3. `does not meet UI component syntax` → 通常是上游模块加载失败的级联错误，修好上游即可消失
