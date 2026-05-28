import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'

export const Route = createFileRoute('/(public)/privacy')({
  component: PrivacyPolicyRoute,
})

const section = 'bg-[#121214] border border-[#2e2e36] rounded-xl p-6 space-y-4'
const title = 'text-lg font-semibold text-[#e4e4e7]'
const text = 'text-sm text-[#a1a1aa] leading-relaxed'
const link = 'text-emerald-500 hover:text-emerald-400 transition-colors underline'

function PrivacyPolicyRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className="text-3xl font-bold tracking-tight">{t('legal.privacy.title')}</h1>
      <p className="text-sm text-[#71717a]">{t('legal.lastUpdated')}</p>

      <div className={section}>
        <h2 className={title}>{t('legal.privacy.section1Title')}</h2>
        <p className={text}>{t('legal.privacy.section1Desc')}</p>
        <ul className="space-y-3">
          <li>
            <strong className="text-[#e4e4e7] text-sm">{t('legal.privacy.info1Title')}</strong>
            <p className={text}>{t('legal.privacy.info1Desc')}</p>
          </li>
          <li>
            <strong className="text-[#e4e4e7] text-sm">{t('legal.privacy.info2Title')}</strong>
            <p className={text}>{t('legal.privacy.info2Desc')}</p>
          </li>
          <li>
            <strong className="text-[#e4e4e7] text-sm">{t('legal.privacy.info3Title')}</strong>
            <p className={text}>{t('legal.privacy.info3Desc')}</p>
          </li>
        </ul>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.privacy.section2Title')}</h2>
        <p className={`mb-3 ${text}`}>{t('legal.privacy.section2Desc')}</p>
        <ul className="list-disc space-y-1 pl-5 text-sm text-[#a1a1aa]">
          <li>{t('legal.privacy.usage1')}</li>
          <li>{t('legal.privacy.usage2')}</li>
          <li>{t('legal.privacy.usage3')}</li>
        </ul>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.privacy.section3Title')}</h2>
        <p className={text}>{t('legal.privacy.section3Desc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.privacy.section4Title')}</h2>
        <p className={`mb-3 ${text}`}>{t('legal.privacy.section4Desc')}</p>
        <ul className="list-disc space-y-1 pl-5 text-sm text-[#a1a1aa]">
          <li>{t('legal.privacy.thirdParty1')}</li>
          <li>{t('legal.privacy.thirdParty2')}</li>
          <li>{t('legal.privacy.thirdParty3')}</li>
        </ul>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.privacy.section5Title')}</h2>
        <p className="text-sm text-[#a1a1aa]">
          {t('legal.privacy.section5Desc')}{' '}
          <a href="/account-deletion" className={link}>
            {t('legal.privacy.section5Link')}
          </a>
          {t('legal.privacy.section5Suffix')}
        </p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.privacy.section6Title')}</h2>
        <p className="text-sm text-[#a1a1aa]">
          {t('legal.privacy.section6Desc')}{' '}
          <a href={`mailto:${t('legal.contactEmail')}`} className={`inline-flex items-center gap-1 ${link}`}>
            <Mail className="size-3" />
            {t('legal.contactEmail')}
          </a>
        </p>
      </div>
    </PublicPageLayout>
  )
}
