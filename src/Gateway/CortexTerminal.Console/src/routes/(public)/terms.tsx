import { createFileRoute } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { Mail } from 'lucide-react'
import { PublicPageLayout } from '@/features/public'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'

export const Route = createFileRoute('/(public)/terms')({
  component: TermsOfServiceRoute,
})

function TermsOfServiceRoute() {
  const { t } = useTranslation()
  return (
    <PublicPageLayout>
      <h1 className='text-2xl font-bold tracking-tight'>{t('legal.terms.title')}</h1>
      <p className='text-sm text-muted-foreground'>{t('legal.lastUpdated')}</p>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section1Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.terms.section1Desc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section2Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.terms.section2Desc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section3Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.terms.section3Desc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section4Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.terms.section4Desc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section5Title')}</CardTitle>
        </CardHeader>
        <CardContent className='text-sm'>
          <p className='text-muted-foreground'>
            {t('legal.terms.section5Desc')}{' '}
            <a href='/account-deletion' className='text-primary underline'>
              {t('legal.terms.section5LinkAccount')}
            </a>
            {' '}{t('legal.terms.section5And')}{' '}
            <a href='/privacy' className='text-primary underline'>
              {t('legal.terms.section5LinkPrivacy')}
            </a>
            {t('legal.terms.section5Suffix')}
          </p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section6Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.terms.section6Desc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section7Title')}</CardTitle>
        </CardHeader>
        <CardContent>
          <p className='text-sm text-muted-foreground'>{t('legal.terms.section7Desc')}</p>
        </CardContent>
      </Card>

      <Card>
        <CardHeader>
          <CardTitle>{t('legal.terms.section8Title')}</CardTitle>
        </CardHeader>
        <CardContent className='text-sm'>
          <p className='text-muted-foreground'>
            {t('legal.terms.section8Desc')}{' '}
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
