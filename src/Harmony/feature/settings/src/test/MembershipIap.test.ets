import { describe, it, expect } from '@ohos/hypium'
import { HuaweiIapService } from '../main/ets/service/HuaweiIapService'

export default function membershipIapTest() {
  describe('membershipIapTest', () => {
    it('maps_membership_plans_to_huawei_products', 0, () => {
      expect(HuaweiIapService.productForPlan('pro_month')).assertEqual('corterm.pro.month')
      expect(HuaweiIapService.productForPlan('pro_year')).assertEqual('corterm.pro.year')
      expect(HuaweiIapService.productForPlan('pro_lifetime')).assertEqual('corterm.pro.lifetime')
      expect(HuaweiIapService.productForPlan('free')).assertEqual('')
    })

    it('maps_product_types_for_subscriptions_and_lifetime', 0, () => {
      expect(HuaweiIapService.productTypeForPlan('pro_month')).assertEqual(2)
      expect(HuaweiIapService.productTypeForPlan('pro_year')).assertEqual(2)
      expect(HuaweiIapService.productTypeForPlan('pro_lifetime')).assertEqual(1)
    })

    it('parses_purchase_data_and_order_id_fields', 0, () => {
      const data = HuaweiIapService.parsePurchaseData('{"productId":"corterm.pro.year","purchaseToken":"t","purchaseState":0,"payOrderId":"o"}')
      expect(data.productId).assertEqual('corterm.pro.year')
      expect(data.purchaseToken).assertEqual('t')
      expect(data.payOrderId).assertEqual('o')
    })

    it('rejects_malformed_purchase_json', 0, () => {
      let threw = false
      try {
        HuaweiIapService.parsePurchaseData('{bad json')
      } catch (_e) {
        threw = true
      }
      expect(threw).assertTrue()
    })
  })
}
