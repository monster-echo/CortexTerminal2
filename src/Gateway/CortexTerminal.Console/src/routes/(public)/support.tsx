import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export const Route = createFileRoute('/(public)/support')({
  component: SupportRoute,
})

function SupportRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className='text-2xl font-bold tracking-tight'>{t('legal.support.title')}</h1>
      <p className='text-sm text-muted-foreground'>{t('legal.support.subtitle')}</p>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.support.contactTitle')}</CardTitle>
        </CardHeader>
        <CardContent className='space-y-2 text-sm'>
          <div className='flex items-center gap-2'>
            <Mail className='size-4 text-muted-foreground' />
            <strong>{t('legal.support.contactEmailLabel')}</strong>：
            <a href={`mailto:${t('legal.contactEmail')}`} className='text-primary underline'>
              {t('legal.contactEmail')}
            </a>
          </div>
          <p className='text-muted-foreground'>{t('legal.support.contactResponse')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.support.faqTitle')}</CardTitle>
        </CardHeader>
        <CardContent className='space-y-6 text-sm'>
          <div>
            <h3 className='font-medium'>{t('legal.support.faq1Q')}</h3>
            <div className='mt-1 space-y-1 text-muted-foreground'>
              <p>{t('legal.support.faq1A1')}</p>
              <p>{t('legal.support.faq1A2')}</p>
              <p>{t('legal.support.faq1A3')}</p>
            </div>
          </div>
          <div>
            <h3 className='font-medium'>{t('legal.support.faq2Q')}</h3>
            <p className='mt-1 text-muted-foreground'>{t('legal.support.faq2A')}</p>
          </div>
          <div>
            <h3 className='font-medium'>{t('legal.support.faq3Q')}</h3>
            <p className='mt-1 text-muted-foreground'>
              {t('legal.support.faq3A')}{' '}
              <a href='/account-deletion' className='text-primary underline'>
                {t('legal.support.faq3Link')}
              </a>
              {t('legal.support.faq3Suffix')}
            </p>
          </div>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.support.relatedTitle')}</CardTitle>
        </CardHeader>
        <CardContent>
          <ul className='space-y-2 text-sm'>
            <li>
              <a href='/privacy' className='text-primary underline'>
                {t('legal.support.relatedPrivacy')}
              </a>
            </li>
            <li>
              <a href='/terms' className='text-primary underline'>
                {t('legal.support.relatedTerms')}
              </a>
            </li>
          </ul>
        </CardContent>
      </Card>
    </PublicPageLayout>
  )
}
