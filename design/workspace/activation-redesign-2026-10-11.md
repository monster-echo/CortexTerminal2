# 激活工作节点页面改版 — 2026-10-11

## 视觉稿

`worker-activation-concept-v1.png`（850 × 1850 px）。由内置 imagegen 生成，用于表达页面结构与视觉层级；实际界面使用应用主题 token，不直接复用生成图中的颜色和系统状态栏。

提示词摘要：HarmonyOS 中文手机界面；工作节点首次连接；相机扫码为主操作，手动输入为次操作；下方显示电脑端的三步准备说明；深色终端应用语境、克制蓝色强调、无手机硬件框和装饰渐变。

## 信息层级

1. 页面标题和一句说明建立“把电脑加入工作区”的目标。
2. 大面积扫码入口作为主要路径，展示相机权限和扫码错误。
3. 手动输入作为独立次级入口，点击后进入单独的短表单页面。
4. 三步连接说明帮助用户在电脑端找到二维码和激活码。

输入页突出 8 位代码，自动大写并每 4 位插入连字符，只有完整代码才可提交。两个页面保留成功、加载和失败状态；扫码仍接受桌面端 URL 中的 code 参数或直接的激活码。摄像头权限在点击扫码时申请。成功后仍沿导航栈返回来源页。

## 实现文件

- `src/Harmony/feature/auth/src/main/ets/view/ActivateWorkerPage.ets`
- `src/Harmony/feature/auth/src/main/ets/view/EnterActivationCodePage.ets`
- `src/Harmony/common/core/src/main/ets/i18n/strings/zh.ets`
- `src/Harmony/common/core/src/main/ets/i18n/strings/en.ets`

扫码卡片、面板、强调色、边框、错误和成功状态都引用 `app.color` token。已静态核对中英文翻译键完整，且引用的颜色键在 base、light、dark 三套主题均存在。

## 验证状态

没有在此工作树成功构建：Hvigor 初次因缺少 `@ohos/hvigor-ohos-plugin` 失败；接入本机现有 6.23.6 插件后，Hvigor 在项目根节点创建阶段报告 `The root node is not yet available for build`。因此 ArkTS 编译、模拟器安装及页面视觉验收尚未完成。此工作树的 HarmonyOS 依赖环境需要修复后再做最终设备复查。
