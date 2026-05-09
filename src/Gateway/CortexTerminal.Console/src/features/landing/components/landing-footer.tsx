import { useTranslation } from 'react-i18next'

export function LandingFooter() {
  const { t } = useTranslation()

  return (
    <div className="max-w-[960px] mx-auto px-6">
      <footer className="border-t border-[#2e2e36] py-10 flex items-center justify-between flex-wrap gap-4">
        <span className="text-[13px] text-[#71717a]">{t('landing.footerCopy')}</span>
        <div className="flex gap-5">
          <a
            href="https://github.com/monster-echo/CortexTerminal2"
            target="_blank"
            rel="noopener"
            className="text-[13px] text-[#a1a1aa] hover:text-[#e4e4e7] transition-colors no-underline"
          >
            GitHub
          </a>
          <a
            href="https://github.com/monster-echo/CortexTerminal2/issues"
            target="_blank"
            rel="noopener"
            className="text-[13px] text-[#a1a1aa] hover:text-[#e4e4e7] transition-colors no-underline"
          >
            Issues
          </a>
          <a
            href="https://github.com/monster-echo/CortexTerminal2/releases"
            target="_blank"
            rel="noopener"
            className="text-[13px] text-[#a1a1aa] hover:text-[#e4e4e7] transition-colors no-underline"
          >
            Releases
          </a>
        </div>
      </footer>
    </div>
  )
}
