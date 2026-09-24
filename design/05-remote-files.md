# 05 Remote Files

## 1. 定位

Remote File Browser 属于 Workspace。它可以从两个入口进入：

```text
Workspace → 文件
Session → … → 文件
```

两个入口打开同一个页面。

## 2. 根目录

默认根目录固定为 Workspace Root。

例如：

```text
~/Projects/CortexTerminal2
```

终端中执行 `cd /tmp` 不改变文件页的默认根目录，避免上下文漂移。

## 3. 页面结构

```text
文件

Mac mini  >  ~/Projects/CortexTerminal2

📁 lib                              >
📁 packages                         >
📁 docs                             >
📄 pubspec.yaml                    …
📄 README.md                       …
```

## 4. 文件夹

- 点击文件夹进入下一层。
- 使用面包屑 / 当前路径返回上级。
- 不使用复杂桌面树控件。

## 5. 文件

条目可显示：
- 文件名
- 大小
- 修改时间
- 更多菜单

文本文件可预览；不适合预览的文件直接进入操作菜单。

## 6. 文件操作

文件更多菜单：

```text
下载
重命名
复制路径
删除
```

后续实现支持时可增加移动 / 复制。

## 7. 新建与上传

右上角 `+`：

```text
上传文件
新建文件夹
新建文本文件
```

不在页面底部常驻多个大按钮。

## 8. 视觉

文件页属于 Dark Tool Context：
- 深色背景
- 中性色文件/目录图标
- 蓝色仅用于当前操作和可交互重点
- 危险操作使用红色
