import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export const Route = createFileRoute('/(public)/privacy')({
  component: PrivacyPolicyRoute,
})

function PrivacyPolicyRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className='text-2xl font-bold tracking-tight'>{t('legal.privacy.title')}</h1>
      <p className='text-sm text-muted-foreground'>{t('legal.lastUpdated')}</p>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.privacy.section1Title')}</CardTitle>
        </CardHeader>
        <CardContent className='space-y-4'>
          <p className='text-sm text-muted-foreground'>{t('legal.privacy.section1Desc')}</p>
          <ul className='space-y-3 text-sm'>
            <li>
              <strong>{t('legal.privacy.info1Title')}</strong>
              <p className='text-muted-foreground'>{t('legal.privacy.info1Desc')}</p>
            </li>
            <li>
              <strong>{t('legal.privacy.info2Title')}</strong>
              <p className='text-muted-foreground'>{t('legal.privacy.info2Desc')}</p>
            </li>
            <li>
              <strong>{t('legal.privacy.info3Title')}</strong>
              <p className='text-muted-foreground'>{t('legal.privacy.info3Desc')}</p>
            </li>
          </ul>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.privacy.section2Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='mb-3 text-sm text-muted-foreground'>{t('legal.privacy.section2Desc')}</p>
          <ul className='list-disc space-y-1 pl-5 text-sm'>
            <li>{t('legal.privacy.usage1')}</li>
            <li>{t('legal.privacy.usage2')}</li>
            <li>{t('legal.privacy.usage3')}</li>
          </ul>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.privacy.section3Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.privacy.section3Desc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.privacy.section4Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='mb-3 text-sm text-muted-foreground'>{t('legal.privacy.section4Desc')}</p>
          <ul className='list-disc space-y-1 pl-5 text-sm'>
            <li>{t('legal.privacy.thirdParty1')}</li>
            <li>{t('legal.privacy.thirdParty2')}</li>
            <li>{t('legal.privacy.thirdParty3')}</li>
          </ul>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.privacy.section5Title')}</CardTitle>
        </CardHeader>
        <CardContent className='text-sm'>
          <p className='text-muted-foreground'>
            {t('legal.privacy.section5Desc')}{' '}
            <a href='/account-deletion' className='text-primary underline'>
              {t('legal.privacy.section5Link')}
            </a>
            {t('legal.privacy.section5Suffix')}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.privacy.section6Title')}</CardTitle>
        </CardHeader>
        <CardContent className='text-sm'>
          <p className='text-muted-foreground'>
            {t('legal.privacy.section6Desc')}{' '}
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
