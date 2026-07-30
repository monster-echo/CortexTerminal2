import { useMemo, useState } from 'react'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Copy, Loader2 } from 'lucide-react'
import { toast } from 'sonner'
import { useTranslation } from 'react-i18next'
import {
  createConsoleApi,
  type BillingPlan,
  type GenerateRedeemCodesResponse,
} from '@/services/console-api'
import { useAuthStore } from '@/stores/auth-store'
import { Header } from '@/components/layout/header'
import { LanguageSwitcher } from '@/components/layout/language-switcher'
import { Main } from '@/components/layout/main'
import { ProfileDropdown } from '@/components/profile-dropdown'
import { ThemeSwitch } from '@/components/theme-switch'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'

function createApi() {
  return createConsoleApi({
    getToken: () => useAuthStore.getState().auth.accessToken,
    onUnauthorized: () => useAuthStore.getState().auth.reset(),
    onTokenRefreshed: (newToken) =>
      useAuthStore.getState().auth.setAccessToken(newToken),
  })
}

export function RedeemCodesPage() {
  const { t } = useTranslation()
  const api = useMemo(() => createApi(), [])

  const [planCode, setPlanCode] = useState('')
  const [count, setCount] = useState('1')
  const [maxUses, setMaxUses] = useState('1')
  const [expiresAt, setExpiresAt] = useState('')
  const [result, setResult] = useState<GenerateRedeemCodesResponse | null>(null)

  const { data: plans = [], isLoading: plansLoading } = useQuery({
    queryKey: ['billing-plans'],
    queryFn: () => api.listBillingPlans(),
  })

  const selectedPlan = useMemo(
    () => plans.find((p) => p.code === planCode) ?? null,
    [plans, planCode]
  )

  const generateMutation = useMutation({
    mutationFn: () => {
      if (!planCode) {
        throw new Error(t('billing.redeem.errors.selectPlan'))
      }
      const countNum = Number.parseInt(count, 10)
      if (!Number.isFinite(countNum) || countNum <= 0) {
        throw new Error(t('billing.redeem.errors.invalidCount'))
      }
      const maxUsesNum = Number.parseInt(maxUses, 10)
      if (!Number.isFinite(maxUsesNum) || maxUsesNum <= 0) {
        throw new Error(t('billing.redeem.errors.invalidMaxUses'))
      }
      return api.generateRedeemCodes({
        planCode,
        count: countNum,
        maxUses: maxUsesNum,
        expiresAtUtc: expiresAt
          ? new Date(expiresAt).toISOString()
          : undefined,
      })
    },
    onSuccess: (data) => {
      setResult(data)
      toast.success(
        t('billing.redeem.generateSuccess', { count: data.codes.length })
      )
    },
    onError: (error: Error) => {
      toast.error(error.message)
    },
  })

  const copyAll = async () => {
    if (!result) return
    try {
      await navigator.clipboard.writeText(result.codes.join('\n'))
      toast.success(t('billing.redeem.copiedAll'))
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : t('billing.redeem.copyFailed')
      )
    }
  }

  const copyOne = async (code: string) => {
    try {
      await navigator.clipboard.writeText(code)
      toast.success(t('billing.redeem.copiedOne'))
    } catch (error) {
      toast.error(
        error instanceof Error ? error.message : t('billing.redeem.copyFailed')
      )
    }
  }

  return (
    <>
      <Header fixed>
        <LanguageSwitcher />
        <ThemeSwitch />
        <ProfileDropdown />
      </Header>
      <Main>
        <div className='mb-6'>
          <h2 className='text-2xl font-bold tracking-tight'>
            {t('billing.redeem.title')}
          </h2>
          <p className='text-muted-foreground'>
            {t('billing.redeem.subtitle')}
          </p>
        </div>

        <Card className='mb-6'>
          <CardHeader>
            <CardTitle>{t('billing.redeem.generate')}</CardTitle>
          </CardHeader>
          <CardContent className='space-y-4'>
            <div className='space-y-2'>
              <Label>{t('billing.redeem.plan')}</Label>
              {plansLoading ? (
                <div className='flex items-center gap-2 text-sm text-muted-foreground'>
                  <Loader2 className='size-4 animate-spin' />{' '}
                  {t('common.loading')}
                </div>
              ) : (
                <Select
                  value={planCode || '_none'}
                  onValueChange={(v) => {
                    setPlanCode(v === '_none' ? '' : v)
                    setResult(null)
                  }}
                >
                  <SelectTrigger>
                    <SelectValue
                      placeholder={t('billing.redeem.selectPlan')}
                    />
                  </SelectTrigger>
                  <SelectContent>
                    {plans.map((p: BillingPlan) => (
                      <SelectItem key={p.code} value={p.code}>
                        {p.tier} · {p.code} ({p.billingPeriod})
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              )}
              {selectedPlan && (
                <p className='text-xs text-muted-foreground'>
                  {t('billing.redeem.planHint', {
                    period: selectedPlan.billingPeriod,
                    currency: selectedPlan.priceCurrency,
                    price: selectedPlan.priceAmount,
                  })}
                </p>
              )}
            </div>

            <div className='grid gap-4 sm:grid-cols-2'>
              <div className='space-y-2'>
                <Label htmlFor='count'>{t('billing.redeem.count')}</Label>
                <Input
                  id='count'
                  type='number'
                  min={1}
                  value={count}
                  onChange={(e) => {
                    setCount(e.target.value)
                    setResult(null)
                  }}
                />
              </div>
              <div className='space-y-2'>
                <Label htmlFor='max-uses'>{t('billing.redeem.maxUses')}</Label>
                <Input
                  id='max-uses'
                  type='number'
                  min={1}
                  value={maxUses}
                  onChange={(e) => {
                    setMaxUses(e.target.value)
                    setResult(null)
                  }}
                />
              </div>
            </div>

            <div className='space-y-2'>
              <Label htmlFor='expires-at'>
                {t('billing.redeem.expiresAt')}
              </Label>
              <Input
                id='expires-at'
                type='datetime-local'
                value={expiresAt}
                onChange={(e) => {
                  setExpiresAt(e.target.value)
                  setResult(null)
                }}
              />
              <p className='text-xs text-muted-foreground'>
                {t('billing.redeem.expiresAtHint')}
              </p>
            </div>

            <Button
              disabled={generateMutation.isPending}
              onClick={() => generateMutation.mutate()}
            >
              {generateMutation.isPending && (
                <Loader2 className='mr-2 size-4 animate-spin' />
              )}
              {t('billing.redeem.generateButton')}
            </Button>
          </CardContent>
        </Card>

        {result && (
          <Card>
            <CardHeader className='flex-row items-center justify-between space-y-0'>
              <div className='space-y-1'>
                <CardTitle>{t('billing.redeem.generatedCodes')}</CardTitle>
                <p className='text-sm text-muted-foreground'>
                  {t('billing.redeem.batchId')}:{' '}
                  <span className='font-mono'>{result.batchId}</span>{' '}
                  <Badge variant='secondary'>
                    {result.codes.length} {t('billing.redeem.codesUnit')}
                  </Badge>
                </p>
              </div>
              <Button variant='outline' size='sm' onClick={copyAll}>
                <Copy className='mr-2 size-4' />
                {t('billing.redeem.copyAll')}
              </Button>
            </CardHeader>
            <CardContent>
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead className='w-16'>#</TableHead>
                    <TableHead>{t('billing.redeem.codeColumn')}</TableHead>
                    <TableHead className='w-24' />
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {result.codes.map((code, idx) => (
                    <TableRow key={code}>
                      <TableCell className='text-muted-foreground'>
                        {idx + 1}
                      </TableCell>
                      <TableCell>
                        <span className='font-mono text-sm'>{code}</span>
                      </TableCell>
                      <TableCell>
                        <Button
                          variant='ghost'
                          size='sm'
                          onClick={() => copyOne(code)}
                        >
                          <Copy className='size-4' />
                          <span className='sr-only'>
                            {t('billing.redeem.copyOne')}
                          </span>
                        </Button>
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        )}
      </Main>
    </>
  )
}
