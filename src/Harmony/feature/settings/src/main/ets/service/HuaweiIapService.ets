import { common } from '@kit.AbilityKit'
import { iap } from '@kit.IAPKit'
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
    if (data.purchaseState !== 0 || data.productId !== productId || !data.purchaseToken) {
      throw new Error('Huawei did not return a completed purchase for the selected product.')
    }

    // Grant only after the backend has independently verified and persisted the Huawei order.
    await ApiService.verifyHuaweiIap(productId, data.purchaseToken)
    const orderId = data.payOrderId ?? data.orderId
    if (!orderId) throw new Error('Huawei purchase response did not include an order ID.')
    await iap.finishPurchase(context, {
      productType: HuaweiIapService.productTypeForPlan(planCode),
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
        const data = HuaweiIapService.parsePurchaseData(result.purchaseDataList[i])
        if (!data.productId || !data.purchaseToken) continue
        const planCode = data.productId === HuaweiIapService.MONTH_PRODUCT ? 'pro_month'
          : (data.productId === HuaweiIapService.YEAR_PRODUCT ? 'pro_year'
            : (data.productId === HuaweiIapService.LIFETIME_PRODUCT ? 'pro_lifetime' : ''))
        if (planCode.length === 0 || HuaweiIapService.productTypeForPlan(planCode) !== productType) continue
        await ApiService.verifyHuaweiIap(data.productId, data.purchaseToken)
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
