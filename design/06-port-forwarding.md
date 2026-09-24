# 06 Port Forwarding

## 1. 归属

PortForward 属于 Workspace，不属于某个具体 Session。

Session 中的入口只是快捷入口：

```text
Session → … → 端口转发
```

进入后管理当前 Workspace 的全部转发规则。

## 2. 页面结构

```text
端口转发                                  +

8080 → 127.0.0.1:8080             [ ON ]
本地 8080 · 远端 8080                 …

3000 → 127.0.0.1:3000             [ ON ]
本地 3000 · 远端 3000                 …

5432 → 127.0.0.1:5432             [ OFF ]
本地 5432 · 远端 5432                 …
```

## 3. 状态与开关

- ON / Running：绿色语义状态。
- OFF / Stopped：灰色。
- Error：红色。
- Switch 控制启动 / 停止。
- 启动失败用 Toast 或 Inline Error。

## 4. 更多操作

```text
编辑
复制地址
删除
```

删除属于危险操作。

## 5. 新建规则

右上角 `+` 进入新建页：

```text
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

默认：
- 远端地址 `127.0.0.1`。
- 输入远端端口后，本地端口默认同值，用户可修改。

## 6. 生命周期

PortForward 生命周期跟随 Workspace，而不是跟随某个 Session 页面。

离开或关闭某个 Session 不应自动销毁仍处于运行中的 Workspace 端口转发。

## 7. 视觉

端口转发属于 Dark Tool Context。
不使用 Dashboard、图表或每条规则不同颜色。
