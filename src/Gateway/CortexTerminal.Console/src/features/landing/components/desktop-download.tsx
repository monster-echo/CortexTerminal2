import { useEffect, useState } from 'react'
import { useTranslation } from 'react-i18next'
import { Download } from 'lucide-react'

interface UiRelease {
  tag_name: string
  assets: Array<{ name: string; browser_download_url: string }>
}

// 桌面端平台卡片：按 release 资产扩展名匹配安装包
const PLATFORMS = [
  { key: 'macos', label: 'landing.downloadMacos', match: (n: string) => n.endsWith('.dmg') },
  { key: 'windows', label: 'landing.downloadWindows', match: (n: string) => n.endsWith('.exe') },
  { key: 'linux', label: 'landing.downloadLinux', match: (n: string) => n.endsWith('.tar.gz') },
]

/**
 * 桌面端（云枢终端）下载卡片。拉取 GitHub releases 找最新 `ui-` tag，
 * 按扩展名给出 macOS .dmg / Windows .exe / Linux .tar.gz 的直链。
 */
export function DesktopDownload() {
  const { t } = useTranslation()
  const [release, setRelease] = useState<UiRelease | null>(null)

  useEffect(() => {
    fetch('https://api.github.com/repos/monster-echo/CortexTerminal2/releases?per_page=30')
      .then((r) => (r.ok ? r.json() : null))
      .then((releases: Array<UiRelease> | null) => {
        const ui = releases?.find((r) => r.tag_name.startsWith('ui-'))
        if (ui) setRelease(ui)
      })
      .catch(() => {})
  }, [])

  const fallbackUrl = release
    ? `https://github.com/monster-echo/CortexTerminal2/releases/tag/${release.tag_name}`
    : 'https://github.com/monster-echo/CortexTerminal2/releases'

  return (
    <div className="flex flex-col gap-3">
      {PLATFORMS.map((p) => {
        const asset = (release?.assets ?? []).find((a) => p.match(a.name))
        const href = asset?.browser_download_url ?? fallbackUrl
        return (
          <a
            key={p.key}
            href={href}
            target="_blank"
            rel="noopener"
            className="flex items-center justify-between gap-3 rounded-lg border border-[#2e2e36] bg-[#121214] px-4 py-3 no-underline transition-all hover:border-emerald-500"
          >
            <span className="flex items-center gap-3">
              <Download className="h-4 w-4 text-emerald-500" />
              <span className="text-sm text-[#e4e4e7]">{t(p.label)}</span>
            </span>
            {release && (
              <span className="font-mono text-xs text-[#71717a]">
                {t('landing.downloadLatest', { version: release.tag_name.replace(/^ui-/, 'v') })}
              </span>
            )}
          </a>
        )
      })}
    </div>
  )
}
