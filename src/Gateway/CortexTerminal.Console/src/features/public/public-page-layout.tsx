import { Link } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { LandingFooter } from '@/features/landing/components/landing-footer'

export function PublicPageLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { i18n } = useTranslation()

  const toggleLang = () => {
    const next = i18n.language === 'zh' ? 'en' : 'zh'
    i18n.changeLanguage(next)
  }

  return (
    <div className="fixed inset-0 overflow-y-auto bg-[#0a0a0b] text-[#e4e4e7] antialiased">
      <div className="fixed inset-0 pointer-events-none z-0">
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_80%_60%_at_50%_-20%,rgba(16,185,129,0.04),transparent_70%)]" />
        <div className="absolute inset-0 bg-[radial-gradient(ellipse_50%_40%_at_80%_80%,rgba(6,182,212,0.03),transparent_70%)]" />
      </div>

      <div className="relative z-[1] max-w-[960px] mx-auto px-6">
        <nav className="flex items-center justify-between py-5 border-b border-[#2e2e36]">
          <div className="flex items-center gap-4">
            <Link to="/" className="flex items-center gap-2 no-underline">
              <span className="w-2 h-2 rounded-full bg-emerald-500 shadow-[0_0_8px_#10b981]" />
              <span className="font-mono text-lg font-bold text-[#e4e4e7] tracking-tight">
                Corterm
              </span>
            </Link>
            <span className="text-sm text-[#71717a]">/</span>
          </div>
          <div className="flex items-center gap-4">
            <button
              className="px-3 py-1.5 rounded-md text-[13px] font-semibold bg-[#242429] border border-[#2e2e36] text-[#a1a1aa] hover:bg-[#1a1a1d] hover:text-[#e4e4e7] hover:border-emerald-500 transition-all leading-none min-w-[40px] text-center cursor-pointer"
              onClick={toggleLang}
              title="Switch Language"
            >
              {i18n.language === 'zh' ? '中' : 'EN'}
            </button>
          </div>
        </nav>

        <div className="py-10 space-y-6">
          {children}
        </div>
      </div>

      <div className="relative z-[1]">
        <LandingFooter />
      </div>
    </div>
  )
}
