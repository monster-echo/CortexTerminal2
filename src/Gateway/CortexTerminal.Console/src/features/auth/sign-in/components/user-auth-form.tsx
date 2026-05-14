import { useState, useEffect, useCallback, useRef } from 'react'
import { z } from 'zod'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { useNavigate } from '@tanstack/react-router'
import { Loader2, LogIn } from 'lucide-react'
import { toast } from 'sonner'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth-store'
import { Button } from '@/components/ui/button'
import {
  Form,
  FormControl,
  FormField,
  FormItem,
  FormMessage,
} from '@/components/ui/form'
import { Input } from '@/components/ui/input'
import { Tabs, TabsContent, TabsList, TabsTrigger } from '@/components/ui/tabs'
import { createConsoleApi } from '@/services/console-api'
import 'altcha'

interface UserAuthFormProps extends React.HTMLAttributes<HTMLDivElement> {
  redirectTo?: string
}

export function UserAuthForm({
  redirectTo,
}: UserAuthFormProps) {
  const [isLoading, setIsLoading] = useState(false)
  const [codeCountdown, setCodeCountdown] = useState(0)
  const [codeSending, setCodeSending] = useState(false)
  const altchaRef = useRef<HTMLElement & { getPayload: () => Promise<string>; resume: () => void }>(null)
  const navigate = useNavigate()
  const { auth } = useAuthStore()
  const { t } = useTranslation()
  const consoleApi = createConsoleApi()

  useEffect(() => {
    if (codeCountdown <= 0) return
    const timer = setTimeout(() => setCodeCountdown(codeCountdown - 1), 1000)
    return () => clearTimeout(timer)
  }, [codeCountdown])

  const passwordSchema = z.object({
    username: z.string().min(1, t('auth.validation.usernameRequired')),
    password: z.string().min(1, t('auth.validation.passwordRequired')),
  })

  const passwordForm = useForm<z.infer<typeof passwordSchema>>({
    resolver: zodResolver(passwordSchema),
    defaultValues: {
      username: '',
      password: '',
    },
  })

  const phoneSchema = z.object({
    phone: z.string().regex(/^1\d{10}$/, t('auth.validation.phoneInvalid')),
    code: z.string().length(6, t('auth.validation.codeLength')),
  })

  const phoneForm = useForm<z.infer<typeof phoneSchema>>({
    resolver: zodResolver(phoneSchema),
    defaultValues: {
      phone: '',
      code: '',
    },
  })

  const handleSendCode = useCallback(async () => {
    const phone = phoneForm.getValues('phone')
    if (!/^1\d{10}$/.test(phone)) {
      phoneForm.setError('phone', { message: t('auth.validation.phoneInvalid') })
      return
    }

    const altchaPayload = altchaRef.current ? await altchaRef.current.getPayload() : null
    if (!altchaPayload) {
      toast.error(t('auth.error.verificationRequired'))
      return
    }

    setCodeSending(true)
    try {
      const res = await fetch('/api/auth/phone/send-code', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone, altcha: altchaPayload }),
      })
      if (!res.ok) {
        const data = await res.json().catch(() => ({}))
        if (res.status === 429) {
          toast.error(t('auth.error.codeRateLimited'))
        } else {
          toast.error(data.error || t('auth.error.codeSendFailed'))
        }
        return
      }
      setCodeCountdown(60)
      toast.success(t('auth.codeSent'))
    } catch {
      toast.error(t('auth.error.codeSendFailed'))
    } finally {
      setCodeSending(false)
      altchaRef.current?.resume()
    }
  }, [phoneForm, t])

  async function onPhoneSubmit(data: z.infer<typeof phoneSchema>) {
    setIsLoading(true)
    try {
      const res = await fetch('/api/auth/phone/verify', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ phone: data.phone, code: data.code }),
      })
      if (!res.ok) {
        const err = await res.json().catch(() => ({}))
        toast.error(err.error || t('auth.loginFailed', { error: '' }))
        return
      }
      const result = await res.json()
      auth.setUser({ username: result.username })
      auth.setAccessToken(result.accessToken)
      toast.success(t('auth.signedInAs', { username: result.username }))
      navigate({ to: redirectTo || '/dashboard', replace: true })
    } catch {
      toast.error(t('auth.loginFailed', { error: '' }))
    } finally {
      setIsLoading(false)
    }
  }

  async function onPasswordSubmit(data: z.infer<typeof passwordSchema>) {
    setIsLoading(true)
    try {
      const result = await consoleApi.login(data.username, data.password)
      auth.setUser({ username: result.username })
      auth.setAccessToken(result.token)
      toast.success(t('auth.signedInAs', { username: result.username }))
      navigate({ to: redirectTo || '/dashboard', replace: true })
    } catch (err) {
      const message = err instanceof Error ? err.message : ''
      toast.error(t('auth.loginFailed', { error: message }))
    } finally {
      setIsLoading(false)
    }
  }

  function handleOAuth(provider: string) {
    const redirect = redirectTo || '/sessions'
    window.location.href = `/api/auth/${provider}?redirect=${encodeURIComponent(redirect)}`
  }

  return (
    <div className='w-full grid gap-3'>
      <Tabs defaultValue="password" className="w-full">
        <TabsList className="w-full">
          <TabsTrigger value="password" className="flex-1">
            {t('auth.signIn')}
          </TabsTrigger>
          <TabsTrigger value="phone" className="flex-1">
            {t('auth.signInWithPhone')}
          </TabsTrigger>
        </TabsList>

        {/* Password login tab */}
        <TabsContent value="password" className="w-full">
          <Form {...passwordForm}>
            <form
              onSubmit={passwordForm.handleSubmit(onPasswordSubmit)}
              className="w-full grid gap-3"
            >
              <FormField
                control={passwordForm.control}
                name="username"
                render={({ field }) => (
                  <FormItem>
                    <FormControl>
                      <Input
                        placeholder={t('auth.username')}
                        autoComplete="username"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <FormField
                control={passwordForm.control}
                name="password"
                render={({ field }) => (
                  <FormItem>
                    <FormControl>
                      <Input
                        placeholder={t('auth.password')}
                        type="password"
                        autoComplete="current-password"
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              <Button type="submit" disabled={isLoading}>
                {isLoading ? <Loader2 className="animate-spin" /> : <LogIn />}
                {t('auth.signIn')}
              </Button>
            </form>
          </Form>
        </TabsContent>

        {/* Phone login tab */}
        <TabsContent value="phone" className="w-full">
          <Form {...phoneForm}>
            <form onSubmit={phoneForm.handleSubmit(onPhoneSubmit)} className="w-full grid gap-3">
              <FormField
                control={phoneForm.control}
                name="phone"
                render={({ field }) => (
                  <FormItem>
                    <FormControl>
                      <Input
                        placeholder={t('auth.phonePlaceholder')}
                        autoComplete="tel"
                        maxLength={11}
                        {...field}
                      />
                    </FormControl>
                    <FormMessage />
                  </FormItem>
                )}
              />
              {/* Altcha PoW verification widget */}
              {/* eslint-disable-next-line @typescript-eslint/no-explicit-any */}
              <altcha-widget
                ref={altchaRef as any}
                challengeurl="/api/auth/altcha/challenge"
                name="altcha"
                hidelogo
                hidefooter
                style={{ width: '100%' }}
              />
              <div className="flex gap-2">
                <FormField
                  control={phoneForm.control}
                  name="code"
                  render={({ field }) => (
                    <FormItem className="flex-1">
                      <FormControl>
                        <Input
                          placeholder={t('auth.codePlaceholder')}
                          autoComplete="one-time-code"
                          maxLength={6}
                          {...field}
                        />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />
                <Button
                  type="button"
                  variant="outline"
                  onClick={handleSendCode}
                  disabled={codeCountdown > 0 || codeSending}
                  className="shrink-0"
                >
                  {codeSending
                    ? <Loader2 className="h-4 w-4 animate-spin" />
                    : codeCountdown > 0
                      ? t('auth.codeCountdown', { seconds: codeCountdown })
                      : t('auth.sendCode')
                  }
                </Button>
              </div>
              <Button type="submit" disabled={isLoading}>
                {isLoading ? <Loader2 className="animate-spin" /> : <LogIn />}
                {t('auth.signIn')}
              </Button>
            </form>
          </Form>
        </TabsContent>
      </Tabs>

      {/* Divider */}
      <div className="relative my-2">
        <div className="absolute inset-0 flex items-center">
          <span className="w-full border-t" />
        </div>
        <div className="relative flex justify-center text-xs uppercase">
          <span className="bg-background px-2 text-muted-foreground">
            {t('auth.or')}
          </span>
        </div>
      </div>

      {/* OAuth buttons */}
      <div className='grid gap-3'>
        <Button variant="outline" onClick={() => handleOAuth('github')}>
          <svg className="mr-2 h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
            <path d="M12 0c-6.626 0-12 5.373-12 12 0 5.302 3.438 9.8 8.207 11.387.599.111.793-.261.793-.577v-2.234c-3.338.726-4.033-1.416-4.033-1.416-.546-1.387-1.333-1.756-1.333-1.756-1.089-.745.083-.729.083-.729 1.205.084 1.839 1.237 1.839 1.237 1.07 1.834 2.807 1.304 3.492.997.107-.775.418-1.305.762-1.604-2.665-.305-5.467-1.334-5.467-5.931 0-1.311.469-2.381 1.236-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.322 3.301 1.23.957-.266 1.983-.399 3.003-.404 1.02.005 2.047.138 3.006.404 2.291-1.552 3.297-1.23 3.297-1.23.653 1.653.242 2.874.118 3.176.77.84 1.235 1.911 1.235 3.221 0 4.609-2.807 5.624-5.479 5.921.43.372.823 1.102.823 2.222v3.293c0 .319.192.694.801.576 4.765-1.589 8.199-6.086 8.199-11.386 0-6.627-5.373-12-12-12z"/>
          </svg>
          {t('auth.signInWith', { provider: 'GitHub' })}
        </Button>
        <Button variant="outline" onClick={() => handleOAuth('google')}>
          <svg className="mr-2 h-4 w-4" viewBox="0 0 24 24">
            <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92a5.06 5.06 0 0 1-2.2 3.32v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.1z" fill="#4285F4"/>
            <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
            <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
            <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
          </svg>
          {t('auth.signInWith', { provider: 'Google' })}
        </Button>
        <Button variant="outline" onClick={() => handleOAuth('apple')}>
          <svg className="mr-2 h-4 w-4" viewBox="0 0 24 24" fill="currentColor">
            <path d="M17.05 20.28c-.98.95-2.05.88-3.08.4-1.09-.5-2.08-.48-3.24 0-1.44.62-2.2.44-3.06-.4C2.79 15.25 3.51 7.59 9.05 7.31c1.35.07 2.29.74 3.08.8 1.18-.24 2.31-.93 3.57-.84 1.51.12 2.65.72 3.4 1.8-3.12 1.87-2.38 5.98.48 7.13-.57 1.5-1.31 2.99-2.54 4.09zM12.03 7.25c-.15-2.23 1.66-4.07 3.74-4.25.29 2.58-2.34 4.5-3.74 4.25z"/>
          </svg>
          {t('auth.signInWith', { provider: 'Apple' })}
        </Button>
      </div>
    </div>
  )
}
