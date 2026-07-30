import { useMemo, useState } from 'react'
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { Loader2, Search } from 'lucide-react'
import { toast } from 'sonner'
import { useTranslation } from 'react-i18next'
import {
  createConsoleApi,
  type BillingPlan,
  type GrantMembershipResponse,
  type UserSummary,
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

function createApi() {
  return createConsoleApi({
    getToken: () => useAuthStore.getState().auth.accessToken,
    onUnauthorized: () => useAuthStore.getState().auth.reset(),
    onTokenRefreshed: (newToken) =>
      useAuthStore.getState().auth.setAccessToken(newToken),
  })
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}

export function MembershipManagementPage() {
  const { t } = useTranslation()
  const api = useMemo(() => createApi(), [])
  const queryClient = useQueryClient()

  const [search, setSearch] = useState('')
  const [selectedUserId, setSelectedUserId] = useState('')
  const [planCode, setPlanCode] = useState('')
  const [expiresAt, setExpiresAt] = useState('')
  const [result, setResult] = useState<GrantMembershipResponse | null>(null)

  const { data: users = [], isLoading: usersLoading } = useQuery({
    queryKey: ['users'],
    queryFn: () => api.listUsers(),
  })

  const { data: plans = [], isLoading: plansLoading } = useQuery({
    queryKey: ['billing-plans'],
    queryFn: () => api.listBillingPlans(),
  })

  const filteredUsers = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return users
    return users.filter(
      (u: UserSummary) =>
        u.name.toLowerCase().includes(q) ||
        u.email.toLowerCase().includes(q) ||
        u.id.toLowerCase().includes(q)
    )
  }, [users, search])

  const selectedUser = useMemo(
    () => users.find((u) => u.id === selectedUserId) ?? null,
    [users, selectedUserId]
  )

  const grantMutation = useMutation({
    mutationFn: () => {
      if (!selectedUserId) {
        throw new Error(t('billing.membership.errors.selectUser'))
      }
      if (!planCode) {
        throw new Error(t('billing.membership.errors.selectPlan'))
      }
      return api.grantMembership({
        userId: selectedUserId,
        planCode,
        expiresAtUtc: expiresAt
          ? new Date(expiresAt).toISOString()
          : undefined,
      })
    },
    onSuccess: (data) => {
      setResult(data)
      toast.success(t('billing.membership.grantSuccess'))
      void queryClient.invalidateQueries({ queryKey: ['users'] })
    },
    onError: (error: Error) => {
      toast.error(error.message)
    },
  })

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
            {t('billing.membership.title')}
          </h2>
          <p className='text-muted-foreground'>
            {t('billing.membership.subtitle')}
          </p>
        </div>

        <Card className='mb-6'>
          <CardHeader>
            <CardTitle>{t('billing.membership.findUser')}</CardTitle>
          </CardHeader>
          <CardContent className='space-y-4'>
            <div className='space-y-2'>
              <Label htmlFor='user-search'>
                {t('billing.membership.searchLabel')}
              </Label>
              <div className='relative'>
                <Search className='pointer-events-none absolute left-3 top-1/2 size-4 -translate-y-1/2 text-muted-foreground' />
                <Input
                  id='user-search'
                  className='pl-9'
                  placeholder={t('billing.membership.searchPlaceholder')}
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                />
              </div>
            </div>

            {usersLoading ? (
              <div className='flex items-center gap-2 text-sm text-muted-foreground'>
                <Loader2 className='size-4 animate-spin' />{' '}
                {t('common.loading')}
              </div>
            ) : filteredUsers.length === 0 ? (
              <p className='text-sm text-muted-foreground'>
                {t('billing.membership.noUsers')}
              </p>
            ) : (
              <div className='space-y-2'>
                <Label>{t('billing.membership.selectUser')}</Label>
                <Select
                  value={selectedUserId || '_none'}
                  onValueChange={(v) => {
                    setSelectedUserId(v === '_none' ? '' : v)
                    setResult(null)
                  }}
                >
                  <SelectTrigger>
                    <SelectValue
                      placeholder={t('billing.membership.selectUser')}
                    />
                  </SelectTrigger>
                  <SelectContent>
                    {filteredUsers.map((u: UserSummary) => (
                      <SelectItem key={u.id} value={u.id}>
                        {u.name} &lt;{u.email}&gt;
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
            )}

            {selectedUser && (
              <div className='rounded-md border p-3 text-sm'>
                <div className='flex flex-wrap items-center gap-2'>
                  <span className='font-medium'>{selectedUser.name}</span>
                  <Badge variant='secondary'>{selectedUser.role}</Badge>
                  <Badge variant='outline'>{selectedUser.status}</Badge>
                </div>
                <p className='mt-1 text-muted-foreground'>
                  {selectedUser.email}
                </p>
              </div>
            )}
          </CardContent>
        </Card>

        <Card>
          <CardHeader>
            <CardTitle>{t('billing.membership.grantMembership')}</CardTitle>
          </CardHeader>
          <CardContent className='space-y-4'>
            <div className='space-y-2'>
              <Label>{t('billing.membership.plan')}</Label>
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
                      placeholder={t('billing.membership.selectPlan')}
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
            </div>

            <div className='space-y-2'>
              <Label htmlFor='expires-at'>
                {t('billing.membership.expiresAt')}
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
                {t('billing.membership.expiresAtHint')}
              </p>
            </div>

            <Button
              disabled={grantMutation.isPending}
              onClick={() => grantMutation.mutate()}
            >
              {grantMutation.isPending && (
                <Loader2 className='mr-2 size-4 animate-spin' />
              )}
              {t('billing.membership.grant')}
            </Button>

            {result && (
              <div className='rounded-md border border-primary/40 bg-primary/5 p-4 text-sm'>
                <p className='font-medium'>
                  {t('billing.membership.resultTier')}:{' '}
                  <span className='font-mono'>{result.tier}</span>
                </p>
                <p className='mt-1 text-muted-foreground'>
                  {t('billing.membership.resultExpiry')}:{' '}
                  {formatDateTime(result.expiresAtUtc)}
                </p>
                <p className='mt-1 text-xs text-muted-foreground'>
                  {t('billing.membership.resultSubscription')}:{' '}
                  <span className='font-mono'>{result.subscriptionId}</span>
                </p>
              </div>
            )}
          </CardContent>
        </Card>
      </Main>
    </>
  )
}
