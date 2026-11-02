# App Store 元数据：EULA / 订阅披露

对应 2026-11 审核驳回（Guideline 3.1.2）：App 提供 Corterm Pro Monthly / Yearly 自动续期订阅，但 App 元数据（每个本地化）没有可用的使用条款（EULA）链接。

## 结论

App Store Connect 的「许可协议（License Agreement）」留空，即使用 Apple 标准 EULA。按审核员的原文要求，把标准 EULA 链接写进每个本地化的 App 描述：

```
https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
```

隐私政策链接（App 信息里的 Privacy Policy URL 也必须是它）：

```
https://corterm.rwecho.top/privacy
```

## 当前状态（2026-11-03）

- ASC 版本 `0.2.32`（REJECTED）的 en-US / zh-Hans 描述已通过 API 写入新文案（1543 / 754 字符），末尾含 EULA、隐私政策、支持链接；版本仍处于 REJECTED，未重新提交。
- 「许可协议」字段保持留空，即 Apple 标准 EULA；未设置自定义 EULA。
- 隐私政策 URL 目前指向 `https://gateway.ct.rwecho.top/privacy`（可用，与 `corterm.rwecho.top` 为同一站点）。描述里用的是 canonical 的 `corterm.rwecho.top`，如需完全一致可把该字段也改成它。
- App 内会员购买页已新增「使用条款（EULA）」「隐私政策」链接，从 `0.2.33+203184` 起生效，需要重新出包才会进入审核包。
- 待办：在 Resolution Center 回复（见文末），然后重新提交。若想让 App 内链接随审核包生效，上传 0.2.33 后提交该版本，而不是直接重提 0.2.32。

## App Store Connect 操作

1. **App 信息 → 隐私政策 URL**：保持 `https://corterm.rwecho.top/privacy`（或现有可用地址）。
2. **App 信息 → 许可协议**：留空（标准 Apple EULA）。不要在这里粘贴 Corterm 自己的《服务条款》，否则产品页会展示自定义 EULA，与描述里的链接不一致。
3. **版本页 → 描述**：已写入 en-US 与 zh-Hans；后续新版本会复制上一版元数据，提交前确认链接行仍在。
4. 在该版本的「App 审核信息 → 备注」说明已为所有本地化补充 EULA 链接，并回复审核消息（见文末）。
5. 如果 ASC 里还有 en-US / zh-Hans 之外的本地化，同样在描述末尾追加 EULA 与隐私政策两行。

App 内已同步补齐：会员购买页（Pro 订阅区）新增「使用条款（EULA）」「隐私政策」链接，满足 3.1.2 对 App 内链接的要求。

## en-US 描述

```
Corterm brings your self-hosted terminal workspace to iPhone and iPad. Install a Worker on your server, Mac, PC, or container host, connect it to your Gateway, and start shell sessions from anywhere.

Use Corterm to:
• create and reconnect terminal sessions on your own machines
• manage online workers and check their status
• activate workers with a simple device-flow code
• keep long-running sessions available across reconnects
• work with a touch-friendly mobile interface

Corterm is built for developers, operators, and power users who want remote terminal access without handing infrastructure to a third-party cloud.

You host the Gateway. You run the Workers. Your sessions stay yours.

CORTERM PRO
Corterm Pro raises the limits for connected computers and terminal scrollback.
• Corterm Pro Monthly — auto-renewable subscription, 1 month
• Corterm Pro Yearly — auto-renewable subscription, 12 months
• Corterm Pro Lifetime — one-time purchase, does not renew

Payment is charged to your Apple Account when you confirm the purchase. A subscription renews automatically unless auto-renew is turned off at least 24 hours before the end of the current period, and your account is charged for renewal within 24 hours before that period ends. Manage or cancel in Settings → Apple Account → Subscriptions. Prices are shown in the app and on the App Store.

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://corterm.rwecho.top/privacy
Support: https://corterm.rwecho.top/support
```

## zh-Hans 描述

```
云枢终端将你的自托管终端工作区带到 iPhone 和 iPad。你可以在服务器、Mac、PC 或容器主机上安装 Worker，连接到自己的 Gateway，然后随时随地发起 Shell 会话。

你可以用云枢终端：
• 在自己的机器上创建并恢复终端会话
• 管理在线 Worker，查看节点状态
• 通过设备码快速激活 Worker
• 在断线后继续访问长时间运行的会话
• 使用针对触控优化的移动端界面完成日常运维

云枢终端适合开发者、运维人员和高级用户，帮助你在不依赖第三方托管平台的前提下安全访问自己的基础设施。

Gateway 由你部署，Worker 由你运行，终端会话也始终由你掌控。

CORTERM PRO 会员
Corterm Pro 提供更高的连接电脑数量与终端回滚额度。
• Corterm Pro Monthly — 自动续期订阅，周期 1 个月
• Corterm Pro Yearly — 自动续期订阅，周期 12 个月
• Corterm Pro Lifetime — 一次性购买，不会续期

确认购买后，费用将从你的 Apple 账户扣款。订阅会自动续期，除非你在当前周期结束前至少 24 小时关闭自动续费；续期费用将在周期结束前 24 小时内扣取。你可以在「设置 → Apple 账户 → 订阅」中管理或取消订阅。价格以应用内和 App Store 显示为准。

使用条款（EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
隐私政策：https://corterm.rwecho.top/privacy
支持：https://corterm.rwecho.top/support
```

## 备选：自定义 EULA

如果要改用 Corterm 自己的《服务条款》作为 EULA，必须两处同时改，否则仍会被拒：

1. App 信息 → 许可协议：粘贴自定义 EULA 全文（该字段只接受文本，不是 URL）。
2. 描述里的链接改为 `https://corterm.rwecho.top/terms`，并把 `legal_links.dart` 的 `termsOfUse` 同步改为该地址后重新出包。

同时应先把《服务条款》补上订阅与自动续期条款（现有条款只覆盖服务使用，没有计费、续期、退款内容）。

## 回复审核（英文）

```
Hello,

We have updated the App Store description for every localization of Corterm (en-US and zh-Hans). Each description now ends with a functional link to the Terms of Use (EULA):

Terms of Use (EULA): https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://corterm.rwecho.top/privacy

Corterm uses Apple's standard EULA; the License Agreement field in App Store Connect is intentionally left blank. The descriptions also disclose the auto-renewable subscriptions (Corterm Pro Monthly, 1 month; Corterm Pro Yearly, 12 months), that payment is charged to the Apple Account at confirmation, and how to manage or cancel renewal.

We also added the Terms of Use (EULA) and Privacy Policy links to the subscription screen inside the app.

Thank you.
```

## 回复审核（中文）

```
您好，

我们已为 Corterm 的每个本地化（en-US、zh-Hans）更新 App Store 描述，末尾均包含可用的使用条款（EULA）链接：

使用条款（EULA）：https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
隐私政策：https://corterm.rwecho.top/privacy

Corterm 使用 Apple 标准 EULA，App Store Connect 中的「许可协议」字段保持留空。描述中也已披露自动续期订阅（Corterm Pro Monthly，1 个月；Corterm Pro Yearly，12 个月）、确认购买时向 Apple 账户扣款，以及如何管理或取消续期。

我们同时在 App 内的订阅页面补充了使用条款（EULA）和隐私政策链接。

谢谢。
```