import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'

export const Route = createFileRoute('/(public)/support')({
  component: SupportRoute,
})

const section = 'bg-[#121214] border border-[#2e2e36] rounded-xl p-6 space-y-4'
const title = 'text-lg font-semibold text-[#e4e4e7]'
const text = 'text-sm text-[#a1a1aa] leading-relaxed'
const link = 'text-emerald-500 hover:text-emerald-400 transition-colors underline'

function SupportRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className="text-3xl font-bold tracking-tight">{t('legal.support.title')}</h1>
      <p className="text-sm text-[#71717a]">{t('legal.support.subtitle')}</p>

      <div className={section}>
        <h2 className={title}>{t('legal.support.contactTitle')}</h2>
        <div className="flex items-center gap-2 text-sm">
          <Mail className="size-4 text-[#71717a]" />
          <strong className="text-[#e4e4e7]">{t('legal.support.contactEmailLabel')}</strong>：
          <a href={`mailto:${t('legal.contactEmail')}`} className={link}>
            {t('legal.contactEmail')}
          </a>
        </div>
        <p className={text}>{t('legal.support.contactResponse')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.support.faqTitle')}</h2>
        <div className="space-y-6">
          <div>
            <h3 className="font-medium text-sm text-[#e4e4e7]">{t('legal.support.faq1Q')}</h3>
            <div className="mt-1 space-y-1">
              <p className={text}>{t('legal.support.faq1A1')}</p>
              <p className={text}>{t('legal.support.faq1A2')}</p>
              <p className={text}>{t('legal.support.faq1A3')}</p>
            </div>
          </div>
          <div>
            <h3 className="font-medium text-sm text-[#e4e4e7]">{t('legal.support.faq2Q')}</h3>
            <p className={`mt-1 ${text}`}>{t('legal.support.faq2A')}</p>
          </div>
          <div>
            <h3 className="font-medium text-sm text-[#e4e4e7]">{t('legal.support.faq3Q')}</h3>
            <p className="mt-1 text-sm text-[#a1a1aa]">
              {t('legal.support.faq3A')}{' '}
              <a href="/account-deletion" className={link}>
                {t('legal.support.faq3Link')}
              </a>
              {t('legal.support.faq3Suffix')}
            </p>
          </div>
        </div>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.support.relatedTitle')}</h2>
        <ul className="space-y-2 text-sm">
          <li>
            <a href="/privacy" className={link}>
              {t('legal.support.relatedPrivacy')}
            </a>
          </li>
          <li>
            <a href="/terms" className={link}>
              {t('legal.support.relatedTerms')}
            </a>
          </li>
        </ul>
      </div>
    </PublicPageLayout>
  )
}
