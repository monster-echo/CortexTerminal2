/**
 * @file FileTypeIcon.ets
 * @brief Type-icon builder mapping a FileCategory to a colored badge + short label.
 *
 * Renders a 48x48 box with a tinted background and a 1-3 letter abbreviation,
 * matching the WeChat file helper visual style.
 */
import { FileCategory } from '../model/ArtifactModels'

@Component
export struct FileTypeIcon {
  @Prop category: string = FileCategory.UNKNOWN
  @Prop filename: string = ''

  build() {
    Row()
      .width(48)
      .height(48)
      .borderRadius(10)
      .backgroundColor(this.iconBg())
      .justifyContent(FlexAlign.Center)
      .alignItems(VerticalAlign.Center) {
        Text(this.shortLabel())
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.terminal_on_secondary_container'))
      }
  }

  private iconBg(): ResourceColor {
    switch (this.category) {
      case FileCategory.IMAGE:
        return '#7cacf8'
      case FileCategory.PDF:
        return '#f4212e'
      case FileCategory.VIDEO:
        return '#892adc'
      case FileCategory.AUDIO:
        return '#00ba7c'
      case FileCategory.ARCHIVE:
        return '#cf9c2a'
      case FileCategory.CODE:
        return '#1d9bf0'
      case FileCategory.TEXT:
        return '#71767b'
      default:
        return '#536471'
    }
  }

  private shortLabel(): string {
    switch (this.category) {
      case FileCategory.IMAGE:
        return 'IMG'
      case FileCategory.PDF:
        return 'PDF'
      case FileCategory.VIDEO:
        return 'MP4'
      case FileCategory.AUDIO:
        return 'MP3'
      case FileCategory.ARCHIVE:
        return 'ZIP'
      case FileCategory.CODE:
        return this.codeExtLabel()
      case FileCategory.TEXT:
        return 'TXT'
      default:
        return this.unknownExtLabel()
    }
  }

  private codeExtLabel(): string {
    const ext = this.upperExtension()
    return ext.length === 0 ? 'CODE' : ext.substring(0, 3)
  }

  private unknownExtLabel(): string {
    const ext = this.upperExtension()
    return ext.length === 0 ? 'FILE' : ext.substring(0, 3)
  }

  private upperExtension(): string {
    const lower = this.filename.toLowerCase()
    const dotIdx = lower.lastIndexOf('.')
    if (dotIdx < 0 || dotIdx === lower.length - 1) {
      return ''
    }
    return lower.substring(dotIdx + 1).toUpperCase()
  }
}
