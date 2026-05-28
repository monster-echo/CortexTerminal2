import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'

export const Route = createFileRoute('/(public)/terms')({
  component: TermsOfServiceRoute,
})

const section = 'bg-[#121214] border border-[#2e2e36] rounded-xl p-6 space-y-4'
const title = 'text-lg font-semibold text-[#e4e4e7]'
const text = 'text-sm text-[#a1a1aa] leading-relaxed'
const link = 'text-emerald-500 hover:text-emerald-400 transition-colors underline'

function TermsOfServiceRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className="text-3xl font-bold tracking-tight">{t('legal.terms.title')}</h1>
      <p className="text-sm text-[#71717a]">{t('legal.lastUpdated')}</p>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section1Title')}</h2>
        <p className={text}>{t('legal.terms.section1Desc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section2Title')}</h2>
        <p className={text}>{t('legal.terms.section2Desc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section3Title')}</h2>
        <p className={text}>{t('legal.terms.section3Desc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section4Title')}</h2>
        <p className={text}>{t('legal.terms.section4Desc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section5Title')}</h2>
        <p className="text-sm text-[#a1a1aa]">
          {t('legal.terms.section5Desc')}{' '}
          <a href="/account-deletion" className={link}>
            {t('legal.terms.section5LinkAccount')}
          </a>
          {' '}{t('legal.terms.section5And')}{' '}
          <a href="/privacy" className={link}>
            {t('legal.terms.section5LinkPrivacy')}
          </a>
          {t('legal.terms.section5Suffix')}
        </p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section6Title')}</h2>
        <p className={text}>{t('legal.terms.section6Desc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section7Title')}</h2>
        <p className={text}>{t('legal.terms.section7Desc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.terms.section8Title')}</h2>
        <p className="text-sm text-[#a1a1aa]">
          {t('legal.terms.section8Desc')}{' '}
          <a href={`mailto:${t('legal.contactEmail')}`} className={`inline-flex items-center gap-1 ${link}`}>
            <Mail className="size-3" />
            {t('legal.contactEmail')}
          </a>
        </p>
      </div>
    </PublicPageLayout>
  )
}
