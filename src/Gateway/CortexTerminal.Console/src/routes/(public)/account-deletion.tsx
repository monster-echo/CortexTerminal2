import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail, AlertTriangle } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export const Route = createFileRoute('/(public)/account-deletion')({
  component: AccountDeletionRoute,
})

function AccountDeletionRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className='text-2xl font-bold tracking-tight'>{t('legal.accountDeletion.title')}</h1>
      <p className='text-sm text-muted-foreground'>{t('legal.lastUpdated')}</p>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.accountDeletion.stepsTitle')}</CardTitle>
        </CardHeader>
        <CardContent>
          <ol className='list-decimal space-y-2 pl-5 text-sm'>
            <li>{t('legal.accountDeletion.step1')}</li>
            <li>{t('legal.accountDeletion.step2')}</li>
            <li>{t('legal.accountDeletion.step3')}</li>
            <li>{t('legal.accountDeletion.step4')}</li>
            <li>{t('legal.accountDeletion.step5')}</li>
            <li>{t('legal.accountDeletion.step6')}</li>
          </ol>
        </CardContent>
      </Card>

      <Card className='border-destructive/50'>
        <CardHeader>
          <CardTitle>{t('legal.accountDeletion.impactTitle')}</CardTitle>
        </CardHeader>
        <CardContent className='space-y-4'>
          <div className='flex items-start gap-2 rounded-md bg-destructive/10 p-3 text-sm'>
            <AlertTriangle className='mt-0.5 size-4 shrink-0 text-destructive' />
            <strong>{t('legal.accountDeletion.warning')}</strong>
          </div>
          <p className='text-sm text-muted-foreground'>{t('legal.accountDeletion.impactDesc')}</p>
          <ul className='space-y-2 text-sm'>
            <li>
              <strong className='text-destructive'>{t('legal.accountDeletion.immediateDelete')}</strong>：{t('legal.accountDeletion.immediateDeleteItem')}
            </li>
            <li>
              <strong className='text-destructive'>{t('legal.accountDeletion.immediateUnbind')}</strong>：{t('legal.accountDeletion.immediateUnbindItem')}
            </li>
            <li>
              <strong className='text-destructive'>{t('legal.accountDeletion.immediateRevoke')}</strong>：{t('legal.accountDeletion.immediateRevokeItem')}
            </li>
            <li>
              <strong>{t('legal.accountDeletion.immediateMark')}</strong>：{t('legal.accountDeletion.immediateMarkItem')}
            </li>
          </ul>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.accountDeletion.retainedTitle')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='mb-3 text-sm text-muted-foreground'>{t('legal.accountDeletion.retainedDesc')}</p>
          <ul className='list-disc pl-5 text-sm'>
            <li>{t('legal.accountDeletion.retainedItem')}</li>
          </ul>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.accountDeletion.statusTitle')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.accountDeletion.statusDesc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.accountDeletion.helpTitle')}</CardTitle>
        </CardHeader>
        <CardContent className='text-sm'>
          <p className='text-muted-foreground'>
            {t('legal.accountDeletion.helpDesc')}{' '}
            <a href={`mailto:${t('legal.contactEmail')}`} className='inline-flex items-center gap-1 text-primary underline'>
              <Mail className='size-3' />
              {t('legal.contactEmail')}
            </a>
          </p>
        </CardContent>
      </Card>
    </PublicPageLayout>
  )
}
