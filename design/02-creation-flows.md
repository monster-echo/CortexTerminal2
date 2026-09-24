# 02 Creation Flows

## 1. 新建入口

- 工作区 Tab `+` → 新建工作区。
- 电脑 Tab `+` → 新建电脑。
- 侧边栏底部「新建」→ 新建 Session。
- Workspace 内「新建会话」→ 新建 Session，并锁定当前 Workspace。

不使用统一“新建菜单”。

## 2. 新建电脑

真实逻辑是 Worker 配对：

```text
新建电脑

[ 扫码区域 ]
扫描电脑端 Corterm 显示的二维码

—— 或 ——
输入配对码
```

禁止设计成 SSH / RDP / Host / Port / Username / Password 表单。

配对成功后电脑进入电脑列表，可继续创建 Workspace。

## 3. 新建工作区

```text
新建工作区

电脑
Mac mini                         >

文件夹
~/Projects/CortexTerminal2       >

名称
CortexTerminal2

[ 创建工作区 ]
```

规则：
- 电脑必填，仅可选择已配对 Worker。
- 文件夹必填，通过独立文件夹选择页选择。
- 名称默认取文件夹 basename，可修改。

## 4. 文件夹选择

这是独立页面。

关键交互统一为：
- 点击文件夹行 = 进入该目录。
- 底部按钮 = 选择“当前目录”。
- 不在列表行同时承担“进入”和“选中”两种动作。

```text
选择文件夹

电脑
Mac mini

当前位置
~/Projects/CortexTerminal2

子目录
lib                              >
docs                             >
packages                         >

[ 使用当前文件夹 ]
```

只展示目录，不展示普通文件。

## 5. 新建 Session

Session 没有类型。

从侧边栏进入：

```text
新建会话

电脑
Mac mini                         >

工作区
CortexTerminal2                  >

名称（可选）
终端 1

[ 创建会话 ]
```

依赖关系：
1. 先选择电脑。
2. 工作区列表只显示该电脑下的 Workspace。
3. 更换电脑后，已选 Workspace 必须清空。
4. 选择 Workspace 后创建 Session。

从 Workspace 内创建：
- 电脑自动锁定为该 Workspace 的 Worker。
- Workspace 自动锁定为当前 Workspace。
- 不再允许重新组合其他电脑与工作区。

## 6. Session 初始目录

新 Session 的 cwd 固定从 Workspace Root 开始。

Workspace 已经决定：
- Worker
- Remote Folder

因此新建 Session 不再选择路径，也不选择 Claude Code / Codex / Shell 类型。
