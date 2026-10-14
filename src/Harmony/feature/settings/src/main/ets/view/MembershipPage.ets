/**
 * Membership purchase surface for the HarmonyOS client.
 * Membership entitlement is refreshed from the Gateway; purchase state and localized
 * prices are provided by Huawei IAP and verified server-side before delivery.
 */
import { common } from '@kit.AbilityKit'
import {
  ApiService,
  I18n,
  PageLayout,
  RouteName,
  clickHaptic,
  showI18nToast
} from '@rwecho/core'
import { HuaweiIapService, HuaweiStorePrice } from '../service/HuaweiIapService'

interface BillingPlan {
  code: string
  tier: string
  billingPeriod: string
  priceAmount: number
  priceCurrency: string
  maxWorkers: number
  maxScrollbackMegabytes: number
  storePrice: string
  subscriptionGroupId: string
}

@Component
export struct MembershipPage {
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('membershipRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0
  @State isLoading: boolean = true
  @State loadError: string = ''
  @State isActive: boolean = false
  @State expiresAtUtc: string = ''
  @State maxWorkers: number = 1
  @State maxScrollbackMegabytes: number = 10
  @State plans: BillingPlan[] = []
  @State selectedPlanCode: string = ''
  @State isPurchasing: boolean = false
  @State isRestoring: boolean = false
  @State storeReady: boolean = false
  @State storeError: string = ''
  @State storePrices: HuaweiStorePrice[] = []
  @State planCode: string = ''
  @State username: string = ''
  @State agreementAccepted: boolean = false
  @State legalDetails: string = ''

  onRefreshTick() {
    this.loadMembership()
  }

  async aboutToAppear() {
    await this.loadMembership()
    this.loadStoreProducts()
  }

  private async loadMembership() {
    this.isLoading = this.plans.length === 0
    this.loadError = ''
    try {
      const sub = await ApiService.getSubscription()
      this.isActive = (sub['isActive'] as boolean) ?? false
      this.planCode = sub['planCode'] as string
      this.expiresAtUtc = (sub['expiresAtUtc'] as string) ?? ''
      this.maxWorkers = (sub['maxWorkers'] as number) ?? 1
      this.maxScrollbackMegabytes = (sub['maxScrollbackMegabytes'] as number) ?? 10
      const raw = await ApiService.listPlans()
      const mapped: BillingPlan[] = []
      for (let i = 0; i < raw.length; i++) {
        const item = raw[i] as Record<string, Object>
        mapped.push({
          code: item['code'] as string,
          tier: item['tier'] as string,
          billingPeriod: item['billingPeriod'] as string,
          priceAmount: item['priceAmount'] as number,
          priceCurrency: item['priceCurrency'] as string,
          maxWorkers: item['maxWorkers'] as number,
          maxScrollbackMegabytes: item['maxScrollbackMegabytes'] as number,
          storePrice: '',
          subscriptionGroupId: ''
        })
      }
      this.plans = mapped
      this.applyStorePrices()
      if (!this.hasPlan(this.selectedPlanCode, mapped)) {
        this.selectedPlanCode = this.defaultSelection(mapped)
      }
    } catch (e) {
      this.loadError = (e as Error).message || I18n.get('membership.load_failed')
    } finally {
      this.isLoading = false
    }
  }

  private async loadStoreProducts() {
    this.storeError = ''
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const profile = await ApiService.getProfile()
      this.username = (profile['username'] as string) ?? ''
      this.storePrices = await HuaweiIapService.queryPrices(context)
      this.storeReady = this.storePrices.length > 0
      this.storePrices = this.storePrices.slice()
      this.applyStorePrices()
    } catch (e) {
      this.storeReady = false
      this.storeError = (e as Error).message || I18n.get('membership.store_unavailable')
    }
  }

  private applyStorePrices() {
    for (let i = 0; i < this.plans.length; i++) {
      const productId = HuaweiIapService.productForPlan(this.plans[i].code)
      for (let j = 0; j < this.storePrices.length; j++) {
        if (this.storePrices[j].productId === productId) {
          this.plans[i].storePrice = this.storePrices[j].localPrice
          this.plans[i].subscriptionGroupId = this.storePrices[j].subscriptionGroupId
        }
      }
    }
    this.plans = this.plans.slice()
  }

  private canPurchase(): boolean {
    const plan = this.selectedPlan()
    return plan !== null && plan.storePrice.length > 0 && !this.isPurchasing && !this.isRestoring && (plan.code === 'pro_lifetime' || this.agreementAccepted)
  }

  private openLegal(key: string) {
    const param: Record<string, string> = { 'kind': key === 'privacy_policy_url' ? 'privacy' : 'terms' }
    this.pageStack.pushPath({ name: RouteName.LEGAL_DOCUMENT, param: param })
  }

  private async purchaseSelectedPlan() {
    const plan = this.selectedPlan()
    if (plan === null || !this.canPurchase()) return
    this.isPurchasing = true
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      await HuaweiIapService.purchase(context, plan.code)
      AppStorage.setOrCreate<number>('membershipRefreshTick', Date.now())
      await this.loadMembership()
      showI18nToast('membership.purchase_success')
    } catch (e) {
      const errorCode = (e as Record<string, Object>)['code'] as number
      if (errorCode !== 1001860000) {
        showI18nToast('membership.purchase_failed')
        this.storeError = (e as Error).message || I18n.get('membership.purchase_failed')
      }
    } finally {
      this.isPurchasing = false
    }
  }

  private async restorePurchases() {
    if (this.isRestoring || this.isPurchasing) return
    this.isRestoring = true
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const count = await HuaweiIapService.restore(context)
      AppStorage.setOrCreate<number>('membershipRefreshTick', Date.now())
      await this.loadMembership()
      showI18nToast(count > 0 ? 'membership.restore_success' : 'membership.restore_empty')
    } catch (e) {
      this.storeError = (e as Error).message || I18n.get('membership.restore_failed')
      showI18nToast('membership.restore_failed')
    } finally {
      this.isRestoring = false
    }
  }

  private async manageSubscription() {
    try {
      const context = this.getUIContext()?.getHostContext() as common.UIAbilityContext
      const plan = this.selectedPlan()
      let groupId = plan?.subscriptionGroupId ?? ''
      if (groupId.length === 0) {
        for (let i = 0; i < this.plans.length; i++) {
          if (this.plans[i].subscriptionGroupId.length > 0) {
            groupId = this.plans[i].subscriptionGroupId
            break
          }
        }
      }
      await HuaweiIapService.manageSubscriptions(context, groupId)
    } catch (_e) {
      showI18nToast('membership.manage_failed')
    }
  }

  private hasPlan(code: string, plans: BillingPlan[]): boolean {
    for (let i = 0; i < plans.length; i++) {
      if (plans[i].code === code) return true
    }
    return false
  }

  private defaultSelection(plans: BillingPlan[]): string {
    for (let i = 0; i < plans.length; i++) {
      if (plans[i].code === 'pro_year') return plans[i].code
    }
    for (let i = 0; i < plans.length; i++) {
      if (plans[i].tier === 'pro') return plans[i].code
    }
    return plans.length > 0 ? plans[0].code : ''
  }

  private selectedPlan(): BillingPlan | null {
    for (let i = 0; i < this.plans.length; i++) {
      if (this.plans[i].code === this.selectedPlanCode) return this.plans[i]
    }
    return null
  }

  private planName(code: string): string {
    const key = `membership.plan_${code}`
    const value = I18n.get(key)
    return value === key ? code : value
  }

  private currencySymbol(currency: string): string {
    if (currency === 'CNY') return '¥'
    if (currency === 'USD') return '$'
    if (currency === 'EUR') return '€'
    return `${currency} `
  }

  private price(plan: BillingPlan): string {
    if (plan.tier === 'free') return I18n.get('membership.price_free')
    return plan.storePrice.length > 0 ? plan.storePrice : I18n.get('account.price_pending')
  }

  private period(plan: BillingPlan): string {
    if (plan.billingPeriod === 'monthly') return I18n.get('membership.per_month')
    if (plan.billingPeriod === 'yearly') return I18n.get('membership.per_year')
    return I18n.get('membership.lifetime')
  }

  private workersLabel(workers: number): string {
    return workers === 1
      ? I18n.getWithArgs('membership.benefit_worker_one', { 'n': '1' })
      : I18n.getWithArgs('membership.benefit_workers', { 'n': `${workers}` })
  }

  private openRedeem() {
    this.pageStack.pushPath({ name: RouteName.REDEEM })
  }

  build() {
    PageLayout({
      title: I18n.get('membership.title'),
      actionTitle: I18n.get(this.isRestoring ? 'membership.processing' : 'membership.restore_purchase'),
      actionEnabled: !this.isPurchasing && !this.isRestoring,
      onAction: () => { this.restorePurchases() }
    }) {
      Column({ space: 20 }) {
        if (this.isLoading) {
          LoadingProgress().width(32).height(32).color($r('app.color.terminal_text_muted'))
        } else if (this.loadError.length > 0) {
          Text(this.loadError).fontSize(14).fontColor($r('app.color.terminal_error'))
          Button(I18n.get('common.retry')).backgroundColor($r('app.color.terminal_background_panel')).fontColor($r('app.color.terminal_text')).onClick(() => this.loadMembership())
        } else if (this.isActive) {
          this.MemberDetails()
        } else {
          this.UpgradeContent()
        }
        if (this.storeError.length > 0) {
          Text(I18n.get('account.store_unavailable')).fontSize(14).fontColor($r('app.color.terminal_error')).width('100%')
          Button(I18n.get('common.retry')).backgroundColor($r('app.color.terminal_background_panel')).fontColor($r('app.color.terminal_text')).onClick(() => this.loadStoreProducts())
        }
        this.RedeemRow()
        Row({ space: 24 }) {
          Text(I18n.get('settings.footer_terms')).fontSize(13).fontColor($r('app.color.terminal_on_primary_container'))
            .onClick(() => this.openLegal('terms_of_service_url'))
          Text(I18n.get('settings.footer_privacy')).fontSize(13).fontColor($r('app.color.terminal_on_primary_container'))
            .onClick(() => this.openLegal('privacy_policy_url'))
        }.justifyContent(FlexAlign.Center).width('100%').padding({ top: 8, bottom: 24 })
      }.width('100%').padding({ left: 16, right: 16, top: 16 })
    }
  }

  @Builder
  UpgradeContent() {
    Column({ space: 20 }) {
      Column({ space: 8 }) {
        Text('Corterm Pro').fontSize(28).fontWeight(FontWeight.Bold).fontColor($r('app.color.terminal_text'))
        Text(I18n.get('account.pro_description')).fontSize(15).fontColor($r('app.color.terminal_text_muted')).lineHeight(22)
      }.width('100%').alignItems(HorizontalAlign.Start)
      Column() {
        this.DetailRow(I18n.get('membership.benefit_more_workers'), I18n.getWithArgs('membership.workers_quota', { 'n': `${this.selectedPlan()?.maxWorkers ?? 0}` }))
        Divider().color($r('app.color.terminal_border_subtle'))
        this.DetailRow(I18n.get('membership.benefit_scrollback_title'), I18n.getWithArgs('membership.scrollback_quota', { 'n': `${this.selectedPlan()?.maxScrollbackMegabytes ?? 0}` }))
      }.padding(16).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
      Column({ space: 10 }) {
        ForEach(this.plans, (plan: BillingPlan) => {
          if (plan.tier === 'pro') { this.PlanRow(plan) }
        }, (plan: BillingPlan) => plan.code)
      }.width('100%')
      if (this.selectedPlan() !== null && this.selectedPlan()!.storePrice.length > 0) {
        Column({ space: 6 }) {
          Text(this.selectedPlanCode === 'pro_lifetime'
            ? I18n.getWithArgs('membership.one_time_price', { 'price': this.price(this.selectedPlan()!) })
            : I18n.getWithArgs('membership.renewal_price', {
                'price': this.price(this.selectedPlan()!),
                'period': this.selectedPlanCode === 'pro_year' ? I18n.get('membership.year_period') : I18n.get('membership.month_period')
              }))
            .fontSize(14).fontColor($r('app.color.terminal_text')).width('100%')
          if (this.selectedPlanCode !== 'pro_lifetime') {
            Text(I18n.get('membership.cancel_instructions')).fontSize(13)
              .fontColor($r('app.color.terminal_text_muted')).lineHeight(20).width('100%')
            Row({ space: 10 }) {
              Checkbox({ name: 'renewalConsent', group: 'renewalConsentGroup' })
                .select(this.agreementAccepted)
                .onChange((value: boolean) => { this.agreementAccepted = value })
              Text(I18n.get('membership.agreement_accept')).fontSize(13)
                .fontColor($r('app.color.terminal_text')).layoutWeight(1)
            }.width('100%')
            Row({ space: 14 }) {
              Text(I18n.get('membership.service_agreement')).fontSize(13)
                .fontColor($r('app.color.terminal_on_primary_container'))
                .onClick(() => { this.legalDetails = 'service' })
              Text(I18n.get('membership.renewal_agreement')).fontSize(13)
                .fontColor($r('app.color.terminal_on_primary_container'))
                .onClick(() => { this.legalDetails = 'renewal' })
              Text(I18n.get('membership.manage_subscription')).fontSize(13)
                .fontColor($r('app.color.terminal_on_primary_container'))
                .onClick(() => this.manageSubscription())
            }.width('100%')
          }
        }.width('100%')
      }
      if (this.legalDetails.length > 0) {
        Column({ space: 12 }) {
          Text(I18n.get(this.legalDetails === 'service' ? 'membership.service_agreement' : 'membership.renewal_agreement'))
            .fontSize(18).fontWeight(FontWeight.Bold)
          Text(I18n.get(this.legalDetails === 'service' ? 'membership.service_agreement_body' : 'membership.renewal_agreement_body'))
            .fontSize(13).lineHeight(21).fontColor($r('app.color.terminal_text'))
          Button(I18n.get('common.cancel')).onClick(() => { this.legalDetails = '' })
        }.width('100%').padding(16).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
      }
      Button(this.isPurchasing ? I18n.get('membership.processing') :
        (this.canPurchase() ? `${I18n.get('membership.purchase_button')} · ${this.price(this.selectedPlan()!)}` : I18n.get('account.price_pending')))
        .width('100%').height(52).fontSize(16).fontWeight(FontWeight.Medium)
        .backgroundColor($r('app.color.terminal_inverse_surface')).fontColor($r('app.color.terminal_inverse_on_surface'))
        .enabled(this.canPurchase()).onClick(() => this.purchaseSelectedPlan())
      Text(I18n.get(this.selectedPlanCode === 'pro_lifetime' ? 'membership.plan_lifetime_detail' : 'membership.purchase_terms'))
        .fontSize(13).fontColor($r('app.color.terminal_text_muted')).lineHeight(20).width('100%')
    }.width('100%')
  }

  @Builder
  PlanRow(plan: BillingPlan) {
    Row({ space: 12 }) {
      Radio({ value: plan.code, group: 'membershipPlans' }).checked(this.selectedPlanCode === plan.code)
        .radioStyle({ checkedBackgroundColor: $r('app.color.terminal_text'), uncheckedBorderColor: $r('app.color.terminal_border'), indicatorColor: $r('app.color.terminal_background_panel') })
        .enabled(!this.isPurchasing && !this.isRestoring)
        .onChange((checked: boolean) => { if (checked) { this.selectedPlanCode = plan.code; this.agreementAccepted = false } })
      Column({ space: 4 }) {
        Text(this.planName(plan.code)).fontSize(16).fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text'))
        Text(this.period(plan)).fontSize(13).fontColor($r('app.color.terminal_text_muted'))
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Text(this.price(plan)).fontSize(plan.storePrice.length > 0 ? 16 : 13).maxLines(2).textAlign(TextAlign.End).layoutWeight(1).fontWeight(FontWeight.Medium).fontColor($r('app.color.terminal_text'))
    }.width('100%').padding(12).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
      .border({ width: 1, color: this.selectedPlanCode === plan.code ? $r('app.color.terminal_text') : $r('app.color.terminal_border_subtle') })
      .onClick(() => { if (!this.isPurchasing && !this.isRestoring) { this.selectedPlanCode = plan.code; this.agreementAccepted = false } })
  }

  @Builder
  MemberDetails() {
    Column({ space: 20 }) {
      Column({ space: 16 }) {
        Row({ space: 12 }) {
          SymbolGlyph($r('sys.symbol.checkmark_circle')).fontSize(28).fontColor([$r('app.color.terminal_success')])
          Column({ space: 4 }) {
            Text('Corterm Pro').fontSize(24).fontWeight(FontWeight.Bold).fontColor($r('app.color.terminal_text'))
            Text(this.planName(this.planCode)).fontSize(15).fontColor($r('app.color.terminal_success'))
          }.alignItems(HorizontalAlign.Start)
        }.width('100%')
        this.DetailRow(I18n.get('account.valid_until'), this.expiresAtUtc.length > 0 ? this.expiresAtUtc.substring(0, 10) : I18n.get('membership.plan_pro_lifetime'))
      }.padding(16).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
      Column() {
        this.DetailRow(I18n.get('account.devices_quota'), `${this.maxWorkers}`)
        Divider().color($r('app.color.terminal_border_subtle'))
        this.DetailRow(I18n.get('account.scrollback_quota'), `${this.maxScrollbackMegabytes} MB`)
      }.padding(16).borderRadius(12).backgroundColor($r('app.color.terminal_background_panel'))
      if (this.planCode !== 'pro_lifetime') {
        Button(I18n.get('membership.manage_subscription')).width('100%').height(52).fontSize(16)
          .backgroundColor($r('app.color.terminal_inverse_surface')).fontColor($r('app.color.terminal_inverse_on_surface'))
          .enabled(!this.isRestoring && !this.isPurchasing).onClick(() => this.manageSubscription())
        Text(I18n.get('account.huawei_manage_note')).fontSize(13).fontColor($r('app.color.terminal_text_muted')).lineHeight(20)
      }
      Button(I18n.get('account.sync_purchases')).width('100%').height(48)
        .backgroundColor($r('app.color.terminal_background_panel')).fontColor($r('app.color.terminal_text'))
        .enabled(!this.isRestoring && !this.isPurchasing).onClick(() => this.restorePurchases())
    }.width('100%')
  }

  @Builder
  DetailRow(label: string, value: string) {
    Row({ space: 12 }) {
      Text(label).fontSize(15).fontColor($r('app.color.terminal_text')).layoutWeight(1)
      Text(value).fontSize(14).textAlign(TextAlign.End).layoutWeight(1).fontColor($r('app.color.terminal_text_muted'))
    }.width('100%').padding({ top: 10, bottom: 10 })
  }

  @Builder
  RedeemRow() {
    Row() {
      Text(I18n.get('membership.menu_redeem')).fontSize(16).fontColor($r('app.color.terminal_text')).layoutWeight(1)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([$r('app.color.terminal_text_muted')])
    }.width('100%').height(56).padding({ left: 16, right: 16 }).borderRadius(12)
      .backgroundColor($r('app.color.terminal_background_panel')).onClick(() => this.openRedeem())
  }
}
