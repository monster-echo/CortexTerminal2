import { useTranslation } from 'react-i18next'
import { Link } from '@tanstack/react-router'
import { InstallCommand } from './install-command'

export function CtaSection() {
  const { t } = useTranslation()

  return (
    <section className="text-center py-24">
      <div className="max-w-[960px] mx-auto px-6">
        <h2 className="text-[36px] font-bold tracking-tight mb-3">
          {t('landing.ctaTitle')}
        </h2>
        <p className="text-base text-[#a1a1aa] mb-8">
          {t('landing.ctaDesc')}
        </p>
        <div className="flex gap-3 justify-center flex-wrap">
          <Link
            to="/dashboard"
            className="inline-flex items-center gap-1.5 bg-emerald-500 text-black px-6 py-3 rounded-md text-[15px] font-semibold no-underline hover:opacity-90 transition-opacity"
          >
            {t('landing.ctaBtn1')}
          </Link>
          <a
            href="https://github.com/monster-echo/CortexTerminal2"
            target="_blank"
            rel="noopener"
            className="inline-flex items-center gap-1.5 bg-[#242429] border border-[#2e2e36] text-[#e4e4e7] px-6 py-3 rounded-md text-[15px] font-medium no-underline hover:border-emerald-500 hover:bg-[#1a1a1d] transition-all"
          >
            {t('landing.ctaBtn2')}
          </a>
        </div>

        <div className="mt-10">
          <InstallCommand />
        </div>
      </div>
    </section>
  )
}
