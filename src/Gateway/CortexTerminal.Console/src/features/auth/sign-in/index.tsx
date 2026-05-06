import { useEffect } from 'react'
import { useSearch } from '@tanstack/react-router'
import { useTranslation } from 'react-i18next'
import { toast } from 'sonner'
import {
  Card,
  CardContent,
  CardDescription,
  CardFooter,
  CardHeader,
  CardTitle,
} from '@/components/ui/card'
import { AuthLayout } from '../auth-layout'
import { UserAuthForm } from './components/user-auth-form'

export function SignIn() {
  const { redirect, error } = useSearch({ from: '/(auth)/sign-in' })
  const { t } = useTranslation()

  const errorMessages: Record<string, string> = {
    github_denied: t('auth.error.githubDenied'),
    github_token_failed: t('auth.error.githubTokenFailed'),
    github_user_failed: t('auth.error.githubUserFailed'),
    google_denied: t('auth.error.googleDenied'),
    google_token_failed: t('auth.error.googleTokenFailed'),
    google_user_failed: t('auth.error.googleUserFailed'),
    apple_denied: t('auth.error.appleDenied'),
    apple_token_failed: t('auth.error.appleTokenFailed'),
    apple_id_token_missing: t('auth.error.appleIdTokenMissing'),
    apple_id_token_invalid: t('auth.error.appleIdTokenInvalid'),
    apple_user_failed: t('auth.error.appleUserFailed'),
  }

  useEffect(() => {
    if (error) {
      toast.error(errorMessages[error] ?? t('auth.loginFailed', { error }))
    }
  }, [error])

  return (
    <AuthLayout>
      <Card className='max-w-sm gap-4'>
        <CardHeader>
          <CardTitle className='text-lg tracking-tight'>
            {t('brand.name')}
          </CardTitle>
          <CardDescription>
            {t('auth.signInToContinue')}
          </CardDescription>
        </CardHeader>
        <CardContent>
          <UserAuthForm redirectTo={redirect} />
        </CardContent>
        <CardFooter>
          <p className='px-8 text-center text-sm text-muted-foreground'>
            {t('auth.orgAccountHint')}
          </p>
        </CardFooter>
      </Card>
    </AuthLayout>
  )
}
