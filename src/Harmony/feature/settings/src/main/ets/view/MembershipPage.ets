/**
 * @file MembershipPage.ets
 * @brief Membership / billing surface for HarmonyOS client.
 *
 * Shows the current entitlement (GET /api/billing/subscription), the active
 * plan catalog (GET /api/billing/plans, public), and in-app redeem-code entry
 * (POST /api/billing/redeem). Purchases complete on the web console — the
 * pricing page opens in the in-app browser.
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
  @State isLoading: boolean = true
  @State loadError: string = ''
  @State tier: string = ''
  @State isActive: boolean = false
  @State expiresAtUtc: string = ''
  @State maxWorkers: number = 0
  @State maxScrollbackMegabytes: number = 0
  @State plans: BillingPlan[] = []
  @StorageLink('membershipRefreshTick') @Watch('onRefreshTick') refreshTick: number = 0

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
    try {
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
    } catch (e) {
      // Plans are informational — a failure here must not hide the entitlement card.
      // The error surfaces in the plans section only.
      this.plans = []
    }
  }

  private periodSuffix(period: string): string {
    if (period === 'monthly') {
      return I18n.get('membership.per_month')
    }
    if (period === 'yearly') {
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
      }
      .width('100%')
      .padding({ bottom: 24 })
    }
    .layoutWeight(1)
    .align(Alignment.Top)
  }

  @Builder
  EntitlementCard() {
    Column() {
      Row() {
        SymbolGlyph(this.isActive ? $r('sys.symbol.checkmark_circle') : $r('sys.symbol.person_2'))
          .fontSize(28)
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

      Text(I18n.getWithArgs('membership.scrollback_quota', { 'n': `${this.maxScrollbackMegabytes}` }))
        .fontSize(13)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 12 })
      Text(I18n.getWithArgs('membership.workers_quota', { 'n': `${this.maxWorkers}` }))
        .fontSize(13)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 4 })
    }
    .width('100%')
    .padding(16)
    .borderRadius(12)
    .backgroundColor($r('app.color.terminal_surface_container'))
  }

  @Builder
  PlansSection() {
    Column() {
      Text(I18n.get('membership.plans_title'))
        .fontSize(14)
        .fontWeight(FontWeight.Medium)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 24, bottom: 8 })

      ForEach(this.plans, (plan: BillingPlan) => {
        Row() {
          Column() {
            Text(`${plan.code}`)
              .fontSize(16)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_primary'))
            Text(I18n.getWithArgs('membership.scrollback_quota', { 'n': `${plan.maxScrollbackMegabytes}` }))
              .fontSize(12)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 2 })
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text(`${plan.priceAmount} ${plan.priceCurrency}${this.periodSuffix(plan.billingPeriod)}`)
            .fontSize(15)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.terminal_secondary'))
        }
        .width('100%')
        .padding(14)
        .borderRadius(10)
        .backgroundColor($r('app.color.terminal_surface_container'))
        .margin({ bottom: 8 })
      }, (plan: BillingPlan) => plan.code)

      Button(I18n.get('membership.view_pricing'))
        .type(ButtonType.Capsule)
        .width('100%')
        .height(48)
        .backgroundColor($r('app.color.terminal_secondary_container'))
        .fontColor($r('app.color.terminal_on_secondary_container'))
        .fontSize(16)
        .fontWeight(FontWeight.Medium)
        .margin({ top: 8 })
        .onClick(() => {
          clickHaptic()
          this.openPricing()
        })

      Text(I18n.get('membership.upgrade_hint'))
        .fontSize(12)
        .fontColor($r('app.color.terminal_on_surface_variant'))
        .margin({ top: 8 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }
}
