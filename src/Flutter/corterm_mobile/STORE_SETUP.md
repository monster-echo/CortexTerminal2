# Flutter 商店购买配置

发行平台：iOS App Store、Android Google Play。客户端包名 / Bundle ID 为 `top.rwecho.cortexterminal`，以原生工程实际配置为准。

## 商品

| 权益 | App Store 商品 ID | Google Play 默认商品 ID | 类型 |
| --- | --- | --- | --- |
| Pro 月度 | corterm.pro.month | corterm.pro.month | 自动续费订阅 |
| Pro 年度 | corterm.pro.year | corterm.pro.year | 自动续费订阅 |
| Pro 永久 | corterm.pro.lifetime | corterm.pro.lifetime | 非消耗型一次性购买 |

App Store 月/年商品应放在同一订阅组。Google Play 月/年各配置一个有效基础方案；客户端展示商店 SDK 返回的本地价格。Google 商品 ID 可用 Gateway 配置覆盖，不能通过客户端提交任意权益。

已拥有 Pro 时，订阅交由商店管理，避免同时购买两份月/年订阅。永久版可单独购买；永久购买不会自动取消现有订阅，页面提示用户在商店取消原订阅。兑换码入口保留。

## Gateway 环境变量

- `Iap__Apple__BundleId=top.rwecho.cortexterminal`
- `Iap__Apple__Environment=Production`，沙盒联调使用现有 Apple 验证器支持的环境配置。
- `Iap__Apple__SharedSecret`：仅旧版 receipt 验证需要；StoreKit 2 使用签名交易 JWS。
- `Iap__Google__PackageName=top.rwecho.cortexterminal`
- `Iap__Google__ServiceAccountEmail`：具有该应用订单与订阅访问权限的 Google 服务账号。
- `Iap__Google__PrivateKey`：对应 PEM 私钥，支持换行或字面量 `\n`；只进入服务端密钥配置。
- `Iap__Google__AllowTestPurchases=true`：仅内部联调环境启用；默认拒绝测试订单。
- 可选：`Iap__Google__ProMonthProductId`、`ProYearProductId`、`ProLifetimeProductId`。
- `Iap__Google__PushAudience`：Google Pub/Sub authenticated push 的 audience。
- `Iap__Google__PushServiceAccountEmail`：Pub/Sub push 使用的服务账号 email，和 API 访问服务账号可以不同。

服务端缺少验单配置时，商品接口返回 unavailable，客户端不开放购买。上述变量的真实值、商店商品状态、测试账号均需在发行环境配置，本次代码修改未设置真实商店凭据。

## 续费、退款与恢复

- App Store Server Notifications V2 使用 `/api/iap/webhook/apple`，支持官方 JSON `signedPayload` 信封，并兼容已有裸 JWS 调用。失败通知可重试，恢复购买更新已验证的到期时间，过期/撤销凭证不能发放权益。
- Google Play RTDN 配置 Pub/Sub topic 和 authenticated push，地址为 `https://<gateway>/api/iap/google/notifications`。
- Google push 单独验证 Google OIDC 签名、issuer、audience、email 和 email_verified；不接受 App JWT 替代。
- 通知仅作为重新查询 Google Play Developer API 的信号，不信任通知内的权益。重复投递重新查询当前状态；已验证订单和 token 幂等处理。
- token 在数据库中只保存 SHA-256；HTTP 客户端关闭 URL 日志，避免请求地址泄露 token。
- 取消续费但尚未到期的订阅保留权益；暂停、到期、退款等按 Google 的当前状态处理。撤销一个 Google 购买后，重新选择账户仍有效的权益，保留其他永久/有效订阅。
- 未经客户端验证绑定账户的新 token 通知不猜测归属；客户端首次验证或恢复购买完成绑定。Android 登录启动时自动查询已有购买，iOS 提供用户触发的恢复购买。
- Gateway 持久化权益后才确认 Google 交易；客户端验证成功后再完成 StoreKit/Google Play 交易。失败订单保留为待重试，用户可恢复购买。
- PostgreSQL 事务锁保护 Google token 重放和同一用户并发购买；无需新增数据表或数据库迁移。

## 上架前仍需实测

本地构建不能替代商店端验证。必须使用 Sandbox / Play 内部测试验证真实商品加载、购买成功、取消、待付款、网络中断、重复恢复、账号切换、续费、到期、退款，以及通知重投。Google 测试期间仅在隔离环境打开 AllowTestPurchases。

参考：
- https://pub.dev/packages/in_app_purchase
- https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2
- https://docs.cloud.google.com/pubsub/docs/authenticate-push-subscriptions
