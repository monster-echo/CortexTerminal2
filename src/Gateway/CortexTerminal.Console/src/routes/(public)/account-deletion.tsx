import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail, AlertTriangle } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'

export const Route = createFileRoute('/(public)/account-deletion')({
  component: AccountDeletionRoute,
})

const section = 'bg-[#121214] border border-[#2e2e36] rounded-xl p-6 space-y-4'
const title = 'text-lg font-semibold text-[#e4e4e7]'
const text = 'text-sm text-[#a1a1aa] leading-relaxed'
const link = 'text-emerald-500 hover:text-emerald-400 transition-colors underline'

function AccountDeletionRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className="text-3xl font-bold tracking-tight">{t('legal.accountDeletion.title')}</h1>
      <p className="text-sm text-[#71717a]">{t('legal.lastUpdated')}</p>

      <div className={section}>
        <h2 className={title}>{t('legal.accountDeletion.stepsTitle')}</h2>
        <ol className="list-decimal space-y-2 pl-5 text-sm text-[#a1a1aa]">
          <li>{t('legal.accountDeletion.step1')}</li>
          <li>{t('legal.accountDeletion.step2')}</li>
          <li>{t('legal.accountDeletion.step3')}</li>
          <li>{t('legal.accountDeletion.step4')}</li>
          <li>{t('legal.accountDeletion.step5')}</li>
          <li>{t('legal.accountDeletion.step6')}</li>
        </ol>
      </div>

      <div className="bg-[#121214] border border-emerald-500/30 rounded-xl p-6 space-y-4">
        <h2 className={title}>{t('legal.accountDeletion.impactTitle')}</h2>
        <div className="flex items-start gap-2 rounded-md bg-emerald-500/10 p-3 text-sm">
          <AlertTriangle className="mt-0.5 size-4 shrink-0 text-emerald-500" />
          <strong className="text-[#e4e4e7]">{t('legal.accountDeletion.warning')}</strong>
        </div>
        <p className={text}>{t('legal.accountDeletion.impactDesc')}</p>
        <ul className="space-y-2 text-sm">
          <li>
            <strong className="text-emerald-500">{t('legal.accountDeletion.immediateDelete')}</strong>：{t('legal.accountDeletion.immediateDeleteItem')}
          </li>
          <li>
            <strong className="text-emerald-500">{t('legal.accountDeletion.immediateUnbind')}</strong>：{t('legal.accountDeletion.immediateUnbindItem')}
          </li>
          <li>
            <strong className="text-emerald-500">{t('legal.accountDeletion.immediateRevoke')}</strong>：{t('legal.accountDeletion.immediateRevokeItem')}
          </li>
          <li>
            <strong className="text-[#e4e4e7]">{t('legal.accountDeletion.immediateMark')}</strong>：{t('legal.accountDeletion.immediateMarkItem')}
          </li>
        </ul>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.accountDeletion.retainedTitle')}</h2>
        <p className={`mb-3 ${text}`}>{t('legal.accountDeletion.retainedDesc')}</p>
        <ul className="list-disc pl-5 text-sm text-[#a1a1aa]">
          <li>{t('legal.accountDeletion.retainedItem')}</li>
        </ul>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.accountDeletion.statusTitle')}</h2>
        <p className={text}>{t('legal.accountDeletion.statusDesc')}</p>
      </div>

      <div className={section}>
        <h2 className={title}>{t('legal.accountDeletion.helpTitle')}</h2>
        <p className="text-sm text-[#a1a1aa]">
          {t('legal.accountDeletion.helpDesc')}{' '}
          <a href={`mailto:${t('legal.contactEmail')}`} className={`inline-flex items-center gap-1 ${link}`}>
            <Mail className="size-3" />
            {t('legal.contactEmail')}
          </a>
        </p>
      </div>
    </PublicPageLayout>
  )
}
