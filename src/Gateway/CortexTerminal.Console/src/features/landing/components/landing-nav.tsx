import { useTranslation } from 'react-i18next'
import { Link } from '@tanstack/react-router'

export function LandingNav() {
  const { t, i18n } = useTranslation()

  const toggleLang = () => {
    const next = i18n.language === 'zh' ? 'en' : 'zh'
    i18n.changeLanguage(next)
  }

  return (
    <nav className="flex items-center justify-between py-5 border-b border-[#2e2e36]">
      <Link to="/" className="flex items-center gap-2 no-underline">
        <span className="w-2 h-2 rounded-full bg-emerald-500 shadow-[0_0_8px_#10b981]" />
        <span className="font-mono text-lg font-bold text-[#e4e4e7] tracking-tight">
          Corterm
        </span>
      </Link>
      <div className="flex items-center gap-6">
        <button
          className="px-3 py-1.5 rounded-md text-[13px] font-semibold bg-[#242429] border border-[#2e2e36] text-[#a1a1aa] hover:bg-[#1a1a1d] hover:text-[#e4e4e7] hover:border-emerald-500 transition-all leading-none min-w-[40px] text-center cursor-pointer"
          onClick={toggleLang}
          title="Switch Language"
        >
          {i18n.language === 'zh' ? '中' : 'EN'}
        </button>
        <a
          href="https://github.com/monster-echo/CortexTerminal2"
          target="_blank"
          rel="noopener"
          className="text-sm text-[#a1a1aa] hover:text-[#e4e4e7] transition-colors no-underline"
        >
          GitHub
        </a>
        <a
          href="https://github.com/monster-echo/CortexTerminal2#readme"
          target="_blank"
          rel="noopener"
          className="text-sm text-[#a1a1aa] hover:text-[#e4e4e7] transition-colors no-underline"
        >
          Docs
        </a>
        <Link
          to="/dashboard"
          className="px-4 py-1.5 rounded-md text-sm font-mono bg-[#242429] border border-[#2e2e36] text-[#e4e4e7] hover:bg-[#1a1a1d] hover:border-emerald-500 transition-all no-underline"
        >
          {t('landing.navLaunch')}
        </Link>
        <a
          href="https://github.com/monster-echo/CortexTerminal2/releases"
          target="_blank"
          rel="noopener"
          className="px-4 py-1.5 rounded-md text-sm font-mono bg-[#242429] border border-[#2e2e36] text-[#e4e4e7] hover:bg-[#1a1a1d] hover:border-emerald-500 transition-all no-underline"
        >
          v0.2.0
        </a>
      </div>
    </nav>
  )
}
