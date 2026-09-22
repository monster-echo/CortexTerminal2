/**
 * @file ReferralPage.ets
 * @brief Invite & Earn page (GET /api/referral/me, POST /api/referral/apply).
 *
 * Shows the user's invite code with copy + system share, reward history, and a
 * field to apply a friend's invite code (one-shot, server-enforced).
 */
import { ApiService, I18n, PageLayout, showI18nToast, showToast, clickHaptic, lightHaptic } from '@rwecho/core'
import { pasteboard } from '@kit.BasicServicesKit'
import { common } from '@kit.AbilityKit'
import { systemShare } from '@kit.ShareKit'
import { uniformTypeDescriptor } from '@kit.ArkData'

/** One row of the reward history list (parsed from /api/referral/me rewards[]). */
class RewardItem {
  invitedUsername: string = ''
  rewardDays: number = 0
  createdAtText: string = ''
}

@Component
export struct ReferralPage {
  @Consume('pageStack') pageStack: NavPathStack
  @StorageLink('language') currentLanguage: string = 'en'
  @State code: string = ''
  @State invitedCount: number = 0
  @State totalRewardDays: number = 0
  @State rewardDaysConfig: number = 0
  @State rewards: RewardItem[] = []
  @State isLoading: boolean = true
  @State loadError: string = ''
  @State applyCodeInput: string = ''
  @State isApplying: boolean = false

  aboutToAppear(): void {
    this.load()
  }

  private tr(key: string): string {
    return I18n.get(key) + (this.currentLanguage ? '' : '')
  }

  private async load() {
    this.isLoading = true
    this.loadError = ''
    try {
      const data = await ApiService.getReferralSummary()
      this.code = (data['code'] as string) ?? ''
      this.invitedCount = (data['invitedCount'] as number) ?? 0
      this.totalRewardDays = (data['totalRewardDays'] as number) ?? 0
      this.rewardDaysConfig = (data['rewardDaysPerInvite'] as number) ?? 0
      const rawRewards = (data['rewards'] as Object[]) ?? []
      const items: RewardItem[] = []
      for (let i = 0; i < rawRewards.length; i++) {
        const raw = rawRewards[i] as Record<string, Object>
        const item = new RewardItem()
        item.invitedUsername = (raw['invitedUsername'] as string) ?? ''
        item.rewardDays = (raw['rewardDays'] as number) ?? 0
        const createdAt = (raw['createdAtUtc'] as string) ?? ''
        item.createdAtText = createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt
        items.push(item)
      }
      this.rewards = items
    } catch (e) {
      this.loadError = I18n.getWithArgs('referral.load_failed', { 'msg': (e as Error).message })
    } finally {
      this.isLoading = false
    }
  }

  private copyCode() {
    const pasteData = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.code)
    pasteboard.getSystemPasteboard().setData(pasteData)
    showToast(this.tr('referral.copied'))
  }

  private async share() {
    const text = I18n.getWithArgs('referral.share_text', { 'code': this.code })
    const context = getContext(this) as common.UIAbilityContext
    const data: systemShare.SharedData = new systemShare.SharedData({
      utd: uniformTypeDescriptor.UniformDataType.TEXT,
      content: text
    })
    const controller: systemShare.ShareController = new systemShare.ShareController(data)
    await controller.show(context, {
      selectionMode: systemShare.SelectionMode.SINGLE,
      previewMode: systemShare.SharePreviewMode.DETAIL
    })
  }

  private async apply() {
    const code = this.applyCodeInput.trim()
    if (code.length === 0) {
      return
    }
    this.isApplying = true
    try {
      await ApiService.applyReferralCode(code)
      showI18nToast('referral.apply_success')
      this.applyCodeInput = ''
    } catch (e) {
      showToast(I18n.getWithArgs('referral.apply_failed', { 'msg': (e as Error).message }))
    } finally {
      this.isApplying = false
    }
  }

  build() {
    PageLayout({ title: this.tr('referral.title') }) {
      Scroll() {
        Column() {
          if (this.isLoading) {
            LoadingProgress()
              .width(40)
              .height(40)
              .color($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 48 })
          } else if (this.loadError.length > 0) {
            Text(this.loadError)
              .fontSize(14)
              .fontColor($r('app.color.terminal_error'))
              .margin({ top: 48 })
          } else {
            // Hero card: invite code + share
            Column() {
              Text(this.tr('referral.my_code'))
                .fontSize(14)
                .fontColor($r('app.color.terminal_on_primary_container'))
              Text(this.code)
                .fontSize(32)
                .fontWeight(FontWeight.Bold)
                .fontColor($r('app.color.terminal_on_primary_container'))
                .letterSpacing(4)
                .margin({ top: 12 })
              Row({ space: 12 }) {
                Button(this.tr('referral.copy')) {
                  Text(this.tr('referral.copy'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.terminal_on_primary_container'))
                }
                .type(ButtonType.Capsule)
                .height(40)
                .backgroundColor($r('app.color.terminal_on_primary_container'))
                .onClick(() => {
                  clickHaptic()
                  this.copyCode()
                })
                Button(this.tr('referral.share')) {
                  Text(this.tr('referral.share'))
                    .fontSize(14)
                    .fontWeight(FontWeight.Medium)
                    .fontColor($r('app.color.terminal_on_primary_container'))
                }
                .type(ButtonType.Capsule)
                .height(40)
                .backgroundColor($r('app.color.terminal_on_primary_container'))
                .onClick(() => {
                  clickHaptic()
                  this.share()
                })
              }
              .margin({ top: 20 })
            }
            .width('100%')
            .padding({ left: 20, right: 20, top: 24, bottom: 24 })
            .borderRadius(12)
            .backgroundColor($r('app.color.terminal_primary_container'))
            .margin({ top: 16 })

            Text(this.tr('referral.subtitle').replace('{n}', `${this.rewardDaysConfig}`))
              .fontSize(13)
              .fontColor($r('app.color.terminal_on_surface_variant'))
              .margin({ top: 12 })

            // Stats row
            Row() {
              Column() {
                Text(`${this.invitedCount}`)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.terminal_on_surface'))
                Text(this.tr('referral.stats_invited'))
                  .fontSize(12)
                  .fontColor($r('app.color.terminal_on_surface_variant'))
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
              Divider()
                .vertical(true)
                .height(32)
                .color($r('app.color.terminal_outline_variant'))
              Column() {
                Text(`${this.totalRewardDays}`)
                  .fontSize(24)
                  .fontWeight(FontWeight.Bold)
                  .fontColor($r('app.color.terminal_tertiary'))
                Text(this.tr('referral.stats_days'))
                  .fontSize(12)
                  .fontColor($r('app.color.terminal_on_surface_variant'))
                  .margin({ top: 4 })
              }
              .layoutWeight(1)
            }
            .width('100%')
            .padding({ top: 16, bottom: 16 })
            .borderRadius(12)
            .backgroundColor($r('app.color.terminal_surface_container'))
            .margin({ top: 16 })

            // Reward history
            Text(this.tr('referral.rewards_title'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_on_surface'))
              .width('100%')
              .margin({ top: 24, bottom: 8 })
            if (this.rewards.length === 0) {
              Text(this.tr('referral.rewards_empty'))
                .fontSize(13)
                .fontColor($r('app.color.terminal_on_surface_variant'))
                .width('100%')
                .textAlign(TextAlign.Center)
                .padding({ top: 16, bottom: 16 })
                .borderRadius(12)
                .backgroundColor($r('app.color.terminal_surface_container'))
            } else {
              Column() {
                ForEach(this.rewards, (item: RewardItem, index: number) => {
                  Column() {
                    if (index > 0) {
                      Divider()
                        .color($r('app.color.terminal_outline_variant'))
                        .margin({ left: 12 })
                    }
                    Row() {
                      Text(this.tr('referral.reward_item').replace('{n}', `${item.rewardDays}`).replace('{name}', item.invitedUsername))
                        .fontSize(14)
                        .fontColor($r('app.color.terminal_on_surface'))
                        .layoutWeight(1)
                      Text(item.createdAtText)
                        .fontSize(11)
                        .fontColor($r('app.color.terminal_text_tertiary'))
                    }
                    .width('100%')
                    .height(48)
                  }
                  .width('100%')
                }, (item: RewardItem) => `${item.invitedUsername}_${item.createdAtText}`)
              }
              .width('100%')
              .padding({ left: 16, right: 16, top: 4, bottom: 4 })
              .borderRadius(12)
              .backgroundColor($r('app.color.terminal_surface_container'))
            }

            // Apply a friend's code
            Text(this.tr('referral.apply_title'))
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.terminal_on_surface'))
              .width('100%')
              .margin({ top: 24, bottom: 8 })
            Row({ space: 8 }) {
              TextInput({ placeholder: this.tr('referral.apply_placeholder'), text: this.applyCodeInput })
                .layoutWeight(1)
                .height(48)
                .fontSize(16)
                .backgroundColor($r('app.color.terminal_surface_container_high'))
                .borderRadius(8)
                .fontColor($r('app.color.terminal_primary'))
                .placeholderColor($r('app.color.terminal_on_surface_variant'))
                .onChange((value: string) => {
                  this.applyCodeInput = value
                })
              Button(this.isApplying ? '…' : this.tr('referral.apply_button')) {
                Text(this.isApplying ? '…' : this.tr('referral.apply_button'))
                  .fontSize(14)
                  .fontWeight(FontWeight.Medium)
                  .fontColor($r('app.color.terminal_on_primary'))
              }
              .type(ButtonType.Capsule)
              .height(48)
              .backgroundColor($r('app.color.terminal_primary'))
              .enabled(this.applyCodeInput.trim().length > 0 && !this.isApplying)
              .opacity(this.applyCodeInput.trim().length > 0 && !this.isApplying ? 1 : 0.5)
              .onClick(() => {
                lightHaptic()
                this.apply()
              })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }

          Blank().height(32)
        }
        .width('100%')
        .padding({ left: 24, right: 24, top: 8 })
      }
      .width('100%')
      .layoutWeight(1)
      .align(Alignment.Top)
      .scrollBar(BarState.Off)
    }
  }
}
