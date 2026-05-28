import { Link } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { ArrowLeft } from 'lucide-react'
import { Button } from '@/components/ui/button'

export function PublicPageLayout({
  children,
}: {
  children: React.ReactNode
}) {
  const { t } = useTranslation()
  return (
    <div className='min-h-svh bg-background'>
      <div className='mx-auto max-w-3xl px-4 py-8 sm:px-6'>
        <div className='mb-8'>
          <Button variant='ghost' size='sm' asChild>
            <Link to='/'>
              <ArrowLeft className='size-4' />
              {t('legal.backToHome')}
            </Link>
          </Button>
        </div>
        {children}
      </div>
    </div>
  )
}
