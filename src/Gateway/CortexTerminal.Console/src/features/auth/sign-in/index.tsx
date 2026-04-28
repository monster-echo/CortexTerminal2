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

const errorMessages: Record<string, string> = {
  github_denied: 'GitHub authorization was denied.',
  github_token_failed: 'Failed to obtain GitHub access token.',
  github_user_failed: 'Failed to retrieve GitHub user info.',
  google_denied: 'Google authorization was denied.',
  google_token_failed: 'Failed to obtain Google access token.',
  google_user_failed: 'Failed to retrieve Google user info.',
}

export function SignIn() {
  const { redirect, error } = useSearch({ from: '/(auth)/sign-in' })
  const { t } = useTranslation()

  useEffect(() => {
    if (error) {
      toast.error(errorMessages[error] ?? `Login failed: ${error}`)
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
            {import.meta.env.VITE_AUTH_MODE === 'dev'
              ? 'Dev mode: use any username to sign in.'
              : 'Sign in with your organizational account.'}
          </p>
        </CardFooter>
      </Card>
    </AuthLayout>
  )
}
