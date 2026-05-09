import { useTranslation } from 'react-i18next'
import { InstallCommand } from './install-command'

export function HeroSection() {
  const { t } = useTranslation()

  return (
    <section className="text-center pt-24 pb-16">
      <div className="inline-flex items-center gap-1.5 bg-emerald-500/15 border border-emerald-500/20 text-emerald-500 text-[13px] font-medium px-3 py-1 rounded-full mb-7">
        <span className="w-1.5 h-1.5 rounded-full bg-emerald-500 animate-pulse" />
        {t('landing.heroBadge')}
      </div>
      <h1 className="text-[clamp(36px,5.5vw,56px)] font-extrabold tracking-tight leading-[1.1] mb-4">
        {t('landing.heroTitle')}
        <br />
        <span className="text-emerald-500">{t('landing.heroTitleAccent')}</span>
      </h1>
      <p className="text-lg text-[#a1a1aa] max-w-[560px] mx-auto mb-10 leading-relaxed">
        {t('landing.heroDesc')}
      </p>

      <InstallCommand className="mb-4" />

      <p className="text-[13px] text-[#71717a] mb-2">
        {t('landing.installHint')}
      </p>
      <div className="flex justify-center gap-2 flex-wrap">
        {['linux/amd64', 'linux/arm64', 'macOS (Apple Silicon)', 'Windows x64', 'Docker'].map(
          (tag) => (
            <span
              key={tag}
              className="text-xs text-[#71717a] px-2.5 py-[3px] border border-[#2e2e36] rounded-full font-mono"
            >
              {tag}
            </span>
          )
        )}
      </div>
    </section>
  )
}
