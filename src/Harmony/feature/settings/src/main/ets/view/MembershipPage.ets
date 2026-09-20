/**
 * @file MembershipPage.ets
 * @brief Membership / pricing surface for the HarmonyOS client.
 *
 * Layout: current-entitlement summary -> selectable plan cards -> one primary CTA.
 * Data: GET /api/billing/subscription (entitlement) + GET /api/billing/plans (catalog).
 * Purchases are completed on the web console; the CTA opens the pricing page.
 * Redeem codes live behind the AppBar "···" menu (secondary action).
 */
import {
  ApiService,
  I18n,
  PageLayout,
  PageMenuItem,
  RouteName,
  clickHaptic
} from '@rwecho/core'

interface BillingPlan {
  code: string
  tier: string
  billingPeriod: string
  priceAmount: number
  priceCurrency: string
  maxWorkers: number
  maxScrollbackMegabytes: number
}

@Component
export struct MembershipPage {
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('membershipRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0
  @State isLoading: boolean = true
  @State loadError: string = ''
  @State tier: string = ''
  @State isActive: boolean = false
  @State expiresAtUtc: string = ''
  @State maxWorkers: number = 0
  @State maxScrollbackMegabytes: number = 0
  @State plans: BillingPlan[] = []
  @State selectedPlanCode: string = ''

  onRefreshTick() {
    this.loadMembership()
  }

  async aboutToAppear() {
    await this.loadMembership()
  }

  private async loadMembership() {
    this.isLoading = true
    this.loadError = ''
    try {
      const sub = await ApiService.getSubscription()
      this.tier = (sub['tier'] as string) ?? ''
      this.isActive = (sub['isActive'] as boolean) ?? false
      this.expiresAtUtc = (sub['expiresAtUtc'] as string) ?? ''
      this.maxWorkers = (sub['maxWorkers'] as number) ?? 0
      this.maxScrollbackMegabytes = (sub['maxScrollbackMegabytes'] as number) ?? 0
      await this.loadPlans()
    } catch (e) {
      this.loadError = (e as Error).message || I18n.get('membership.load_failed')
    } finally {
      this.isLoading = false
    }
  }

  private async loadPlans() {
    const raw = await ApiService.listPlans()
    const mapped: BillingPlan[] = []
    for (let i = 0; i < raw.length; i++) {
      const item = raw[i] as Record<string, Object>
      const plan: BillingPlan = {
        code: item['code'] as string,
        tier: item['tier'] as string,
        billingPeriod: item['billingPeriod'] as string,
        priceAmount: item['priceAmount'] as number,
        priceCurrency: item['priceCurrency'] as string,
        maxWorkers: item['maxWorkers'] as number,
        maxScrollbackMegabytes: item['maxScrollbackMegabytes'] as number
      }
      mapped.push(plan)
    }
    this.plans = mapped
    if (this.selectedPlanCode.length === 0) {
      this.selectedPlanCode = this.defaultSelection(mapped)
    }
  }

  /** Yearly Pro is the headline offer; fall back to any paid plan, else free. */
  private defaultSelection(plans: BillingPlan[]): string {
    for (let i = 0; i < plans.length; i++) {
      if (plans[i].code === 'pro_year') {
        return plans[i].code
      }
    }
    for (let i = 0; i < plans.length; i++) {
      if (plans[i].tier === 'pro') {
        return plans[i].code
      }
    }
    return plans.length > 0 ? plans[0].code : ''
  }

  private planName(code: string): string {
    const key = `membership.plan_${code}`
    const localized = I18n.get(key)
    return localized === key ? code : localized
  }

  private isRecommended(plan: BillingPlan): boolean {
    return plan.code === 'pro_year'
  }

  private isCurrentPlan(plan: BillingPlan): boolean {
    if (plan.tier === 'free' && !this.isActive) {
      return true
    }
    return this.isActive && plan.tier === 'pro' && plan.code === 'pro_lifetime'
  }

  private priceMain(plan: BillingPlan): string {
    if (plan.tier === 'free') {
      return I18n.get('membership.price_free')
    }
    return `${this.currencySymbol(plan.priceCurrency)}${plan.priceAmount}`
  }

  private currencySymbol(currency: string): string {
    if (currency === 'CNY') {
      return '¥'
    }
    if (currency === 'USD') {
      return '$'
    }
    if (currency === 'EUR') {
      return '€'
    }
    return `${currency} `
  }

  private workersLabel(plan: BillingPlan): string {
    return plan.maxWorkers === 1
      ? I18n.getWithArgs('membership.benefit_worker_one', { 'n': '1' })
      : I18n.getWithArgs('membership.benefit_workers', { 'n': `${plan.maxWorkers}` })
  }

  private currentWorkersLabel(): string {
    return this.maxWorkers === 1
      ? I18n.getWithArgs('membership.benefit_worker_one', { 'n': '1' })
      : I18n.getWithArgs('membership.benefit_workers', { 'n': `${this.maxWorkers}` })
  }

  private pricePeriod(plan: BillingPlan): string {
    if (plan.billingPeriod === 'monthly') {
      return I18n.get('membership.per_month')
    }
    if (plan.billingPeriod === 'yearly') {
      return I18n.get('membership.per_year')
    }
    return I18n.get('membership.lifetime')
  }

  private openPricing() {
    const gatewayUrl = AppStorage.get<string>('gatewayUrl') || ''
    const navParam: Record<string, string> = { 'url': `${gatewayUrl}/pricing` }
    this.pageStack.pushPath({ name: RouteName.WEB_PAGE, param: navParam })
  }

  build() {
    PageLayout({
      title: I18n.get('membership.title'),
      moreMenuItems: this.buildMoreMenu()
    }) {
      Column() {
        if (this.isLoading) {
          Column() {
            LoadingProgress().width(40).height(40).color($r('app.color.terminal_on_surface_variant'))
          }
          .width('100%')
          .padding({ top: 80 })
          .alignItems(HorizontalAlign.Center)
        } else if (this.loadError.length > 0) {
          this.ErrorState()
        } else {
          this.Content()
        }
      }
      .width('100%')
      .layoutWeight(1)
      .padding({ left: 24, right: 24, top: 8 })
    }
  }

  private buildMoreMenu(): PageMenuItem[] {
    const items: PageMenuItem[] = []
    const redeem = new PageMenuItem()
    redeem.value = I18n.get('membership.menu_redeem')
    redeem.action = () => {
      this.pageStack.pushPath({ name: RouteName.REDEEM })
    }
    items.push(redeem)
    return items
  }

  @Builder
  ErrorState() {
    Column() {
      SymbolGlyph($r('sys.symbol.exclamationmark_triangle'))
        .fontSize(40)
        .fontColor([$r('app.color.terminal_error')])
      Text(I18n.get('membership.load_failed'))
        .fontSize(14)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 12 })
      Text(this.loadError)
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 4 })
        .textAlign(TextAlign.Center)
      Button(I18n.get('common.retry'))
        .type(ButtonType.Capsule)
        .height(40)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .margin({ top: 16 })
        .onClick(() => {
          clickHaptic()
          this.loadMembership()
        })
    }
    .width('100%')
    .padding({ top: 60 })
    .alignItems(HorizontalAlign.Center)
  }

  @Builder
  Content() {
    Scroll() {
      Column() {
        this.EntitlementCard()
        this.PlansSection()
        this.CtaSection()
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .layoutWeight(1)
    .align(Alignment.Top)
    .scrollBar(BarState.Off)
  }

  @Builder
  EntitlementCard() {
    Column() {
      Row() {
        SymbolGlyph(this.isActive ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.person_2'))
          .fontSize(26)
          .fontColor([this.isActive ? $r('app.color.terminal_tertiary') : $r('app.color.terminal_on_surface_variant')])
        Column() {
          Text(this.isActive ? I18n.get('membership.current_tier_pro') : I18n.get('membership.current_tier_free'))
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.terminal_primary'))
          if (this.isActive && this.expiresAtUtc.length > 0) {
            Text(I18n.getWithArgs('membership.renews_expire', { 'date': this.expiresAtUtc.substring(0, 10) }))
              .fontSize(12)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.Start)
        .margin({ left: 12 })
        .layoutWeight(1)
      }
      .width('100%')

      Divider()
        .color($r('app.color.terminal_outline_variant'))
        .margin({ top: 14, bottom: 12 })

      Row() {
        Text(this.currentWorkersLabel())
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))
          .layoutWeight(1)
        Text(I18n.getWithArgs('membership.benefit_scrollback', { 'n': `${this.maxScrollbackMegabytes}` }))
          .fontSize(13)
          .fontColor($r('app.color.terminal_on_surface_variant'))
      }
      .width('100%')
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
  }

  @Builder
  PlansSection() {
    Column() {
      Text(I18n.get('membership.choose_plan'))
        .fontSize(16)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.terminal_primary'))
        .width('100%')
        .margin({ top: 24, bottom: 12 })

      ForEach(this.plans, (plan: BillingPlan) => {
        this.PlanCard(plan)
      }, (plan: BillingPlan) => plan.code)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  PlanCard(plan: BillingPlan) {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(this.planName(plan.code))
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_primary'))
            if (this.isRecommended(plan)) {
              Text(I18n.get('membership.recommended'))
                .fontSize(11)
                .fontColor($r('app.color.terminal_on_secondary_container'))
                .backgroundColor($r('app.color.terminal_secondary_container'))
                .borderRadius(8)
                .padding({ left: 6, right: 6, top: 2, bottom: 2 })
                .margin({ left: 8 })
            }
            if (this.isCurrentPlan(plan)) {
              Text(I18n.get('membership.plan_current'))
                .fontSize(11)
                .fontColor($r('app.color.terminal_tertiary'))
                .borderRadius(8)
                .border({ width: 1, color: $r('app.color.terminal_tertiary') })
                .padding({ left: 6, right: 6, top: 1, bottom: 1 })
                .margin({ left: 8 })
            }
          }
          .alignItems(VerticalAlign.Center)

          Row() {
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(13)
              .fontColor([$r('app.color.terminal_tertiary')])
            Text(this.workersLabel(plan))
              .fontSize(12)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ left: 6 })
            SymbolGlyph($r('sys.symbol.checkmark_circle'))
              .fontSize(13)
              .fontColor([$r('app.color.terminal_tertiary')])
              .margin({ left: 12 })
            Text(I18n.getWithArgs('membership.benefit_scrollback', { 'n': `${plan.maxScrollbackMegabytes}` }))
              .fontSize(12)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ left: 6 })
          }
          .width('100%')
          .margin({ top: 8 })
          .alignItems(VerticalAlign.Center)
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Column() {
          Text(this.priceMain(plan))
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor(plan.tier === 'free'
              ? $r('app.color.terminal_on_surface_variant')
              : $r('app.color.terminal_secondary'))
          if (plan.tier !== 'free') {
            Text(this.pricePeriod(plan))
              .fontSize(12)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 2 })
          }
        }
        .alignItems(HorizontalAlign.End)
        .margin({ left: 12 })
      }
      .width('100%')
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor(this.selectedPlanCode === plan.code
      ? $r('app.color.terminal_surface_container_high')
      : $r('app.color.terminal_surface_container'))
    .border({
      width: this.selectedPlanCode === plan.code ? 2 : 1,
      color: this.selectedPlanCode === plan.code
        ? $r('app.color.terminal_secondary_container')
        : $r('app.color.terminal_outline_variant')
    })
    .margin({ bottom: 12 })
    .onClick(() => {
      clickHaptic()
      this.selectedPlanCode = plan.code
    })
  }

  @Builder
  CtaSection() {
    Column() {
      Button(this.selectedTier() === 'free'
        ? I18n.get('membership.cta_manage')
        : I18n.get('membership.cta_upgrade'))
        .type(ButtonType.Capsule)
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .onClick(() => {
          clickHaptic()
          this.openPricing()
        })

      Text(I18n.get('membership.secure_payment'))
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .textAlign(TextAlign.Center)
        .width('100%')
        .margin({ top: 10 })
    }
    .width('100%')
    .margin({ top: 8 })
  }

  private selectedTier(): string {
    for (let i = 0; i < this.plans.length; i++) {
      if (this.plans[i].code === this.selectedPlanCode) {
        return this.plans[i].tier
      }
    }
    return 'free'
  }
}
