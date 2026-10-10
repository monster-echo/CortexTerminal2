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
  PageMenuItem,
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
  @State username: string = ''

  onRefreshTick() {
    this.loadMembership()
  }

  async aboutToAppear() {
    await this.loadMembership()
    this.loadStoreProducts()
  }

  private async loadMembership() {
    this.isLoading = true
    this.loadError = ''
    try {
      const sub = await ApiService.getSubscription()
      this.isActive = (sub['isActive'] as boolean) ?? false
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
      for (let i = 0; i < this.plans.length; i++) {
        const productId = HuaweiIapService.productForPlan(this.plans[i].code)
        for (let j = 0; j < this.storePrices.length; j++) {
          if (this.storePrices[j].productId === productId) {
            this.plans[i].storePrice = this.storePrices[j].localPrice
            this.plans[i].subscriptionGroupId = this.storePrices[j].subscriptionGroupId
            break
          }
        }
      }
      this.plans = this.plans.slice()
    } catch (e) {
      this.storeReady = false
      this.storeError = (e as Error).message || I18n.get('membership.store_unavailable')
    }
  }

  private async purchaseSelectedPlan() {
    const plan = this.selectedPlan()
    if (plan === null || this.isPurchasing || !this.storeReady) return
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
    if (this.isRestoring) return
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
    return plan.storePrice.length > 0 ? plan.storePrice : `${this.currencySymbol(plan.priceCurrency)}${plan.priceAmount}`
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

  private buildMoreMenu(): PageMenuItem[] {
    const item = new PageMenuItem()
    item.value = I18n.get('membership.menu_redeem')
    item.action = (): void => {
      this.openRedeem()
    }
    return [item]
  }

  build() {
    PageLayout({
      title: I18n.get('membership.title'),
      moreMenuItems: this.buildMoreMenu()
    }) {
      if (this.isLoading) {
        Column() {
          LoadingProgress().width(36).height(36).color($r('app.color.terminal_text'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else if (this.loadError.length > 0) {
        this.ErrorState()
      } else {
        this.Content()
      }
    }
  }

  @Builder
  ErrorState() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(38)
        .fontColor([$r('app.color.terminal_error')])
      Text(I18n.get('membership.load_failed'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.terminal_text'))
        .margin({ top: 12 })
      Text(this.loadError)
        .fontSize(12)
        .fontColor($r('app.color.terminal_text_muted'))
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
      Button(I18n.get('common.retry'))
        .type(ButtonType.Capsule)
        .height(42)
        .backgroundColor($r('app.color.terminal_inverse_surface'))
        .fontColor($r('app.color.terminal_inverse_on_surface'))
        .margin({ top: 18 })
        .onClick(() => this.loadMembership())
    }
    .width('100%')
    .height('100%')
    .padding(24)
    .alignItems(HorizontalAlign.Center)
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  Content() {
    Scroll() {
      Column({ space: 18 }) {
        this.Hero()
        this.CurrentPlan()
        this.Benefits()
        this.PlanPicker()
        if (this.isActive) {
          Button(I18n.get('membership.manage_subscription'))
            .type(ButtonType.Normal)
            .width('100%')
            .height(42)
            .backgroundColor($r('app.color.terminal_background_panel'))
            .fontColor($r('app.color.terminal_text'))
            .onClick(() => this.manageSubscription())
        }
        this.TrustNote()
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 8, bottom: 126 })
    }
    .width('100%')
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.Top)
    .overlay(this.PurchaseBar(), { align: Alignment.Bottom })
  }

  @Builder
  Hero() {
    Column() {
      Row() {
        Row({ space: 5 }) {
          Circle().width(6).height(6).fill('#76D7A8')
          Text(I18n.get('membership.hero_eyebrow'))
            .fontSize(11)
            .fontWeight(FontWeight.Bold)
            .fontColor('#B9C7FF')
            .letterSpacing(1.2)
        }
        .padding({ left: 10, right: 10, top: 7, bottom: 7 })
        .borderRadius(20)
        .backgroundColor('#28365D')
        Blank()
        if (this.isActive) {
          Text(I18n.get('membership.current_tier_pro'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor('#B8F1D0')
        }
      }

      Text(I18n.get('membership.hero_title'))
        .fontSize(27)
        .fontWeight(FontWeight.Bold)
        .fontColor(Color.White)
        .lineHeight(34)
        .width('100%')
        .margin({ top: 17 })
      Text(I18n.get('membership.hero_subtitle'))
        .fontSize(13)
        .fontColor('#C1C9DA')
        .lineHeight(20)
        .width('100%')
        .margin({ top: 8 })

      Row() {
        Column() {
          Text('~/corterm')
            .fontSize(10)
            .fontColor('#A7B4D0')
          Row({ space: 5 }) {
            Text('›')
              .fontSize(16)
              .fontWeight(FontWeight.Bold)
              .fontColor('#80E1B0')
            Text(I18n.get('membership.hero_terminal_line'))
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor('#F3F6FC')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Blank()
            Circle().width(6).height(6).fill('#80E1B0')
          }
          .width('100%')
          .margin({ top: 7 })
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
      }
      .width('100%')
      .padding(13)
      .borderRadius(13)
      .backgroundColor('#11192B')
      .margin({ top: 19 })

      Row({ space: 7 }) {
        this.MachinePill('01')
        Text('···').fontSize(13).fontColor('#7C8BAA')
        this.MachinePill('02')
        Text('···').fontSize(13).fontColor('#7C8BAA')
        this.MachinePill('∞')
        Blank()
        Text(I18n.get('membership.hero_network_label'))
          .fontSize(10)
          .fontColor('#A7B4D0')
      }
      .width('100%')
      .margin({ top: 12 })
    }
    .width('100%')
    .padding(20)
    .borderRadius(22)
    .backgroundColor('#19233A')
  }

  @Builder
  MachinePill(index: string) {
    Row({ space: 5 }) {
      Circle().width(5).height(5).fill('#78D9AA')
      Text(index)
        .fontSize(10)
        .fontColor('#DCE5F6')
        .fontFamily('monospace')
    }
    .padding({ left: 8, right: 8, top: 5, bottom: 5 })
    .borderRadius(9)
    .backgroundColor('#283550')
  }

  @Builder
  CurrentPlan() {
    Row({ space: 10 }) {
      SymbolGlyph(this.isActive ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.person_2'))
        .fontSize(18)
        .fontColor([this.isActive ? $r('app.color.terminal_success') : $r('app.color.terminal_text_muted')])
      Column() {
        Text(this.isActive ? I18n.get('membership.current_tier_pro') : I18n.get('membership.current_tier_free'))
          .fontSize(12)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_text'))
        Text(this.isActive && this.expiresAtUtc.length > 0
          ? I18n.getWithArgs('membership.renews_expire', { 'date': this.expiresAtUtc.substring(0, 10) })
          : `${this.workersLabel(this.maxWorkers)} · ${I18n.getWithArgs('membership.benefit_scrollback', { 'n': `${this.maxScrollbackMegabytes}` })}`)
          .fontSize(10)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text(I18n.get('membership.current_plan_label'))
        .fontSize(10)
        .fontColor($r('app.color.terminal_text_muted'))
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 11, bottom: 11 })
    .borderRadius(14)
    .backgroundColor($r('app.color.terminal_background_panel'))
    .border({ width: 1, color: $r('app.color.terminal_border_subtle') })
  }

  @Builder
  Benefits() {
    Column({ space: 1 }) {
      Row() {
        Text(I18n.get('membership.benefits_title'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_text'))
        Blank()
        Text(I18n.get('membership.benefits_caption'))
          .fontSize(11)
          .fontColor($r('app.color.terminal_text_muted'))
      }
      .width('100%')
      .margin({ bottom: 9 })
      this.BenefitRow('◉', I18n.get('membership.benefit_more_workers'), I18n.get('membership.benefit_more_workers_detail'))
      this.BenefitRow('↶', I18n.get('membership.benefit_scrollback_title'), I18n.get('membership.benefit_scrollback_detail'))
      this.BenefitRow('⌘', I18n.get('membership.benefit_control_title'), I18n.get('membership.benefit_control_detail'))
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  BenefitRow(icon: string, title: string, detail: string) {
    Row({ space: 12 }) {
      Text(icon)
        .fontSize(17)
        .fontColor($r('app.color.terminal_text'))
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .borderRadius(11)
        .backgroundColor($r('app.color.terminal_primary_container'))
      Column() {
        Text(title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.terminal_text'))
        Text(detail)
          .fontSize(11)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('✓')
        .fontSize(13)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_success'))
    }
    .width('100%')
    .padding({ top: 8, bottom: 8 })
  }

  @Builder
  PlanPicker() {
    Column() {
      Row() {
        Text(I18n.get('membership.choose_plan'))
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_text'))
        Blank()
        Text(I18n.get('membership.price_note'))
          .fontSize(11)
          .fontColor($r('app.color.terminal_text_muted'))
      }
      .width('100%')
      .margin({ bottom: 10 })

      ForEach(this.plans, (plan: BillingPlan) => {
        if (plan.tier === 'pro') {
          this.PlanRow(plan)
        }
      }, (plan: BillingPlan) => plan.code)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PlanRow(plan: BillingPlan) {
    Row({ space: 11 }) {
      Circle()
        .width(18)
        .height(18)
        .fill(this.selectedPlanCode === plan.code ? $r('app.color.terminal_inverse_surface') : Color.Transparent)
        .border({ width: 1.5, color: this.selectedPlanCode === plan.code ? $r('app.color.terminal_inverse_surface') : $r('app.color.terminal_border') })
      Column() {
        Row({ space: 7 }) {
          Text(this.planName(plan.code))
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_text'))
          if (plan.code === 'pro_year') {
            Text(I18n.get('membership.recommended'))
              .fontSize(9)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.terminal_on_primary_container'))
              .padding({ left: 6, right: 6, top: 3, bottom: 3 })
              .borderRadius(7)
              .backgroundColor($r('app.color.terminal_primary_container'))
          }
        }
        .alignItems(VerticalAlign.Center)
        Text(plan.code === 'pro_year'
          ? I18n.get('membership.plan_year_detail')
          : (plan.code === 'pro_month' ? I18n.get('membership.plan_month_detail') : I18n.get('membership.plan_lifetime_detail')))
          .fontSize(10)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ top: 3 })
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Column() {
        Text(this.price(plan))
          .fontSize(15)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_text'))
        Text(this.period(plan))
          .fontSize(10)
          .fontColor($r('app.color.terminal_text_muted'))
          .margin({ top: 2 })
      }
      .alignItems(HorizontalAlign.End)
    }
    .width('100%')
    .padding({ left: 13, right: 13, top: 12, bottom: 12 })
    .borderRadius(15)
    .backgroundColor(this.selectedPlanCode === plan.code ? $r('app.color.terminal_primary_container') : $r('app.color.terminal_background_panel'))
    .border({
      width: this.selectedPlanCode === plan.code ? 1.5 : 1,
      color: this.selectedPlanCode === plan.code ? $r('app.color.terminal_inverse_surface') : $r('app.color.terminal_border_subtle')
    })
    .margin({ bottom: 8 })
    .onClick(() => {
      clickHaptic()
      this.selectedPlanCode = plan.code
    })
  }

  @Builder
  TrustNote() {
    Row({ space: 7 }) {
      SymbolGlyph($r('sys.symbol.lock_shield'))
        .fontSize(13)
        .fontColor([$r('app.color.terminal_text_muted')])
      Text(this.storeError.length > 0 ? this.storeError : I18n.get('membership.payment_note'))
        .fontSize(10)
        .fontColor($r('app.color.terminal_text_muted'))
        .layoutWeight(1)
    }
    .width('100%')
    .padding({ left: 4, right: 4, top: 4, bottom: 4 })
  }

  @Builder
  PurchaseBar() {
    Column() {
      Row() {
        Column() {
          Text(I18n.get('membership.total_today'))
            .fontSize(10)
            .fontColor($r('app.color.terminal_text_muted'))
          if (this.selectedPlan() !== null) {
            Text(this.price(this.selectedPlan()!))
              .fontSize(21)
              .fontWeight(FontWeight.Bold)
              .fontColor($r('app.color.terminal_text'))
              .margin({ top: 1 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)
        Button(I18n.get('membership.restore_purchase'))
          .type(ButtonType.Normal)
          .fontSize(11)
          .fontColor($r('app.color.terminal_text'))
          .backgroundColor(Color.Transparent)
          .padding({ left: 8, right: 0 })
          .enabled(!this.isRestoring)
          .onClick(() => { clickHaptic(); this.restorePurchases() })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)

        Button(this.isPurchasing ? I18n.get('membership.processing') : I18n.get('membership.purchase_button'))
        .type(ButtonType.Capsule)
        .width('100%')
        .height(48)
        .fontSize(15)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_inverse_on_surface'))
        .backgroundColor($r('app.color.terminal_inverse_surface'))
        .enabled(this.storeReady && !this.isPurchasing && this.selectedPlan() !== null)
        .opacity(this.storeReady && !this.isPurchasing ? 1 : 0.5)
        .margin({ top: 10 })
        .onClick(() => {
          clickHaptic()
          this.purchaseSelectedPlan()
        })
      Text(I18n.get('membership.purchase_terms'))
        .fontSize(9)
        .fontColor($r('app.color.terminal_text_muted'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 7 })
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 10 })
    .backgroundColor($r('app.color.terminal_background'))
    .border({ width: { top: 1 }, color: $r('app.color.terminal_border_subtle') })
  }
}
