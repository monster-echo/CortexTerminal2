import { common } from '@kit.AbilityKit'
import { iap } from '@kit.IAPKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'
import { ApiService } from '@rwecho/core'

export interface HuaweiStorePrice {
  productId: string
  localPrice: string
  subscriptionGroupId: string
}

interface HuaweiPurchaseData {
  productId?: string
  purchaseToken?: string
  purchaseState?: number
  payOrderId?: string
  orderId?: string
  jwsSubscriptionStatus?: string
  jwsPurchaseOrder?: string
}

interface HuaweiJwsOrder {
  orderId?: string
  productId?: string
}

interface HuaweiJwsPayload {
  purchaseOrderId?: string
  purchaseToken?: string
  productId?: string
  subscriptionId?: string
  lastPurchaseOrder?: HuaweiJwsOrder
}

export class HuaweiIapService {
  static readonly MONTH_PRODUCT = 'corterm.pro.month'
  static readonly YEAR_PRODUCT = 'corterm.pro.year'
  static readonly LIFETIME_PRODUCT = 'corterm.pro.lifetime'

  static productForPlan(planCode: string): string {
    if (planCode === 'pro_month') return HuaweiIapService.MONTH_PRODUCT
    if (planCode === 'pro_year') return HuaweiIapService.YEAR_PRODUCT
    if (planCode === 'pro_lifetime') return HuaweiIapService.LIFETIME_PRODUCT
    return ''
  }

  static productTypeForPlan(planCode: string): iap.ProductType {
    return planCode === 'pro_lifetime' ? iap.ProductType.NONCONSUMABLE : iap.ProductType.AUTORENEWABLE
  }

  static parsePurchaseData(raw: string): HuaweiPurchaseData {
    const parsed = JSON.parse(raw) as HuaweiPurchaseData
    return parsed
  }

  /**
   * queryPurchases 返回的 PurchaseData 是 JWS（含 type + jwsPurchaseOrder /
   * jwsSubscriptionStatus），订单字段在 JWS payload 里，需要解开才能拿到。
   */
  static decodeJwsPurchaseData(jws: string): HuaweiPurchaseData {
    const empty: HuaweiPurchaseData = { purchaseState: 0 }
    const parts = jws.split('.')
    if (parts.length < 2) {
      hilog.error(0x0000, 'CortermIAP', 'JWS malformed, segments=%{public}d', parts.length)
      return empty
    }
    try {
      const bytes = new util.Base64Helper().decodeSync(parts[1], util.Type.BASIC_URL_SAFE)
      const json = util.TextDecoder.create('utf-8').decodeToString(bytes)
      const payload = JSON.parse(json) as HuaweiJwsPayload
      hilog.info(0x0000, 'CortermIAP',
        'jws payload: productId=%{public}s tokenLen=%{public}d orderId=%{public}s subscriptionId=%{public}s',
        `${payload.productId ?? ''}`, `${(payload.purchaseToken ?? '').length}`,
        `${payload.purchaseOrderId ?? ''}`, `${payload.subscriptionId ?? ''}`)
      const result: HuaweiPurchaseData = {
        productId: payload.productId,
        purchaseToken: payload.purchaseToken,
        purchaseState: 0,
        orderId: payload.purchaseOrderId ?? payload.lastPurchaseOrder?.orderId
      }
      return result
    } catch (e) {
      hilog.error(0x0000, 'CortermIAP', 'failed to decode JWS payload: %{public}s', `${e}`)
      return empty
    }
  }

  static storePriceFromProduct(product: iap.Product): HuaweiStorePrice {
    return {
      productId: product.id,
      localPrice: product.localPrice ?? product.price,
      subscriptionGroupId: product.subscriptionInfo?.groupId ?? ''
    }
  }

  static async queryPrices(context: common.UIAbilityContext): Promise<HuaweiStorePrice[]> {
    const results: [Array<iap.Product>, Array<iap.Product>] = await Promise.all([
      iap.queryProducts(context, {
        productType: iap.ProductType.AUTORENEWABLE,
        productIds: [HuaweiIapService.MONTH_PRODUCT, HuaweiIapService.YEAR_PRODUCT]
      }),
      iap.queryProducts(context, {
        productType: iap.ProductType.NONCONSUMABLE,
        productIds: [HuaweiIapService.LIFETIME_PRODUCT]
      })
    ])
    const subscriptions = results[0]
    const lifetime = results[1]
    return subscriptions.concat(lifetime).map((product: iap.Product): HuaweiStorePrice =>
      HuaweiIapService.storePriceFromProduct(product))
  }

  static async purchase(context: common.UIAbilityContext, planCode: string): Promise<void> {
    const productId = HuaweiIapService.productForPlan(planCode)
    if (productId.length === 0) throw new Error('Unsupported membership plan.')
    const result = await iap.createPurchase(context, {
      productId,
      productType: HuaweiIapService.productTypeForPlan(planCode),
      applicationUserName: HuaweiIapService.userBinding()
    })
    const data = HuaweiIapService.parsePurchaseData(result.purchaseData)
    hilog.info(0x0000, 'CortermIAP', 'purchase raw: %{public}s', `${result.purchaseData}`)
    hilog.info(0x0000, 'CortermIAP',
      'purchase parsed: state=%{public}s productId=%{public}s tokenLen=%{public}d orderId=%{public}s payOrderId=%{public}s',
      `${data.purchaseState}`, `${data.productId ?? ''}`, `${(data.purchaseToken ?? '').length}`,
      `${data.orderId ?? ''}`, `${data.payOrderId ?? ''}`)
    const productType = HuaweiIapService.productTypeForPlan(planCode)

    // 自动续期订阅：createPurchase 只返回 jwsSubscriptionStatus（ES256 JWS），不含订单字段。
    // 由网关解码验签并发放权益，再回传 finishPurchase 所需的 token / orderId。
    if (productType === iap.ProductType.AUTORENEWABLE) {
      const jws = data.jwsSubscriptionStatus ?? ''
      if (jws.length === 0) {
        throw new Error('Huawei subscription purchase did not include a JWS payload.')
      }
      const verified = await ApiService.verifyHuaweiIapSubscription(jws, productId)
      const purchaseToken = verified['purchaseToken'] as string
      const purchaseOrderId = verified['purchaseOrderId'] as string
      if (purchaseToken && purchaseOrderId) {
        await iap.finishPurchase(context, { productType, purchaseToken, purchaseOrderId })
      }
      return
    }

    // 非消耗型（终身买断）：createPurchase 直接返回订单字段，走服务端订单校验。
    if (data.purchaseState !== 0 || data.productId !== productId || !data.purchaseToken) {
      throw new Error(`Huawei purchase incomplete: state=${data.purchaseState}, productId=${data.productId}, hasToken=${data.purchaseToken !== undefined}`)
    }

    // Grant only after the backend has independently verified and persisted the Huawei order.
    const orderId = data.payOrderId ?? data.orderId
    if (!orderId) throw new Error('Huawei purchase response did not include an order ID.')
    await ApiService.verifyHuaweiIap(productId, data.purchaseToken, orderId)
    await iap.finishPurchase(context, {
      productType: productType,
      purchaseToken: data.purchaseToken,
      purchaseOrderId: orderId
    })
  }

  static userBinding(): string {
    try {
      const info = JSON.parse(AppStorage.get<string>('userInfo') ?? '') as Record<string, string>
      return info['displayName'] ?? ''
    } catch (_e) {
      return ''
    }
  }

  static async restore(context: common.UIAbilityContext): Promise<number> {
    let restored = 0
    restored += await HuaweiIapService.restoreType(context, iap.ProductType.AUTORENEWABLE)
    restored += await HuaweiIapService.restoreType(context, iap.ProductType.NONCONSUMABLE)
    return restored
  }

  private static async restoreType(context: common.UIAbilityContext, productType: iap.ProductType): Promise<number> {
    let count = 0
    let continuationToken: string | undefined = undefined
    do {
      const param: iap.QueryPurchasesParameter = {
        productType: productType,
        queryType: iap.PurchaseQueryType.CURRENT_ENTITLEMENT,
        continuationToken: continuationToken
      }
      const result = await iap.queryPurchases(context, param)
      for (let i = 0; i < result.purchaseDataList.length; i++) {
        hilog.info(0x0000, 'CortermIAP', 'restore raw[%{public}d]: %{public}s', i, `${result.purchaseDataList[i]}`)
        let data = HuaweiIapService.parsePurchaseData(result.purchaseDataList[i])
        if (!data.productId || !data.purchaseToken) {
          // JWS 格式：订单字段在 payload 里，解开再校验
          data = HuaweiIapService.decodeJwsPurchaseData(
            data.jwsPurchaseOrder ?? data.jwsSubscriptionStatus ?? '')
        }
        if (!data.productId || !data.purchaseToken) continue
        const planCode = data.productId === HuaweiIapService.MONTH_PRODUCT ? 'pro_month'
          : (data.productId === HuaweiIapService.YEAR_PRODUCT ? 'pro_year'
            : (data.productId === HuaweiIapService.LIFETIME_PRODUCT ? 'pro_lifetime' : ''))
        if (planCode.length === 0 || HuaweiIapService.productTypeForPlan(planCode) !== productType) continue
        await ApiService.verifyHuaweiIap(data.productId, data.purchaseToken,
          data.orderId ?? data.payOrderId ?? '')
        count++
      }
      continuationToken = result.continuationToken
    } while (continuationToken && continuationToken.length > 0)
    return count
  }

  static async manageSubscriptions(context: common.UIAbilityContext, groupId: string): Promise<void> {
    await iap.showManagedSubscriptions(context, { windowScreenMode: iap.WindowScreenMode.FULLSCREEN }, groupId)
  }
}
