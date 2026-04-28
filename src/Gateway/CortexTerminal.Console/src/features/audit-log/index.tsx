import { useMemo, useState } from 'react'
import { useQuery } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { createConsoleApi, type AuditLogEntry } from '@/services/console-api'
import { useAuthStore } from '@/stores/auth-store'
import { Loader2 } from 'lucide-react'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { ProfileDropdown } from '@/components/profile-dropdown'
import { LanguageSwitcher } from '@/components/layout/language-switcher'
import { ThemeSwitch } from '@/components/theme-switch'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Table, TableBody, TableCell, TableHead, TableHeader, TableRow,
} from '@/components/ui/table'
import {
  Select, SelectContent, SelectItem, SelectTrigger, SelectValue,
} from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'

function createApi() {
  return createConsoleApi({
    getToken: () => useAuthStore.getState().auth.accessToken,
    onUnauthorized: () => useAuthStore.getState().auth.reset(),
  })
}

const ACTION_TYPES = [
  { value: '', label: 'All' },
  { value: 'session.create', label: 'Session Create' },
  { value: 'session.delete', label: 'Session Delete' },
  { value: 'user.login', label: 'User Login' },
  { value: 'user.invite', label: 'User Invite' },
  { value: 'user.update', label: 'User Update' },
  { value: 'user.delete', label: 'User Delete' },
  { value: 'worker.connect', label: 'Worker Connect' },
  { value: 'worker.disconnect', label: 'Worker Disconnect' },
]

const PAGE_SIZE = 20

export function AuditLogPage() {
  const { t } = useTranslation()
  const api = useMemo(() => createApi(), [])
  const [page, setPage] = useState(1)
  const [actionType, setActionType] = useState('')
  const [fromDate, setFromDate] = useState('')
  const [toDate, setToDate] = useState('')

  const { data, isLoading, isError, error } = useQuery({
    queryKey: ['audit-log', page, actionType, fromDate, toDate],
    queryFn: () =>
      api.getAuditLog({
        page,
        pageSize: PAGE_SIZE,
        actionType: actionType || undefined,
        fromDate: fromDate || undefined,
        toDate: toDate || undefined,
      }),
  })

  const entries = data?.entries ?? []
  const totalCount = data?.totalCount ?? 0
  const totalPages = Math.max(1, Math.ceil(totalCount / PAGE_SIZE))

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
            {t('auditLog.title')}
          </h2>
        </div>

        <div className='mb-4 flex flex-wrap items-end gap-3'>
          <div>
            <label className='mb-1 block text-sm font-medium text-muted-foreground'>
              {t('auditLog.action')}
            </label>
            <Select value={actionType || '_all'} onValueChange={(v) => { setActionType(v === '_all' ? '' : v); setPage(1) }}>
              <SelectTrigger className='h-9 w-44'>
                <SelectValue placeholder='All' />
              </SelectTrigger>
              <SelectContent>
                {ACTION_TYPES.map((opt) => (
                  <SelectItem key={opt.value} value={opt.value || '_all'}>
                    {opt.label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>
          <div>
            <label className='mb-1 block text-sm font-medium text-muted-foreground'>
              From
            </label>
            <Input
              type='date'
              className='h-9 w-40'
              value={fromDate}
              onChange={(e) => { setFromDate(e.target.value); setPage(1) }}
            />
          </div>
          <div>
            <label className='mb-1 block text-sm font-medium text-muted-foreground'>
              To
            </label>
            <Input
              type='date'
              className='h-9 w-40'
              value={toDate}
              onChange={(e) => { setToDate(e.target.value); setPage(1) }}
            />
          </div>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>{t('auditLog.title')}</CardTitle>
          </CardHeader>
          <CardContent>
            {isLoading ? (
              <div className='flex items-center gap-2 text-sm text-muted-foreground'>
                <Loader2 className='size-4 animate-spin' /> {t('common.loading')}
              </div>
            ) : isError ? (
              <p className='text-sm text-destructive'>
                {error instanceof Error ? error.message : 'Could not load audit log.'}
              </p>
            ) : entries.length === 0 ? (
              <p className='text-sm text-muted-foreground'>No audit log entries found.</p>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t('auditLog.timestamp')}</TableHead>
                    <TableHead>{t('auditLog.user')}</TableHead>
                    <TableHead>{t('auditLog.action')}</TableHead>
                    <TableHead>{t('auditLog.target')}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {entries.map((entry: AuditLogEntry) => (
                    <TableRow key={entry.id}>
                      <TableCell>{formatDateTime(entry.timestamp)}</TableCell>
                      <TableCell>{entry.userName}</TableCell>
                      <TableCell>
                        <span className='rounded bg-muted px-2 py-0.5 font-mono text-xs'>
                          {entry.action}
                        </span>
                      </TableCell>
                      <TableCell>
                        {entry.targetEntity}/{entry.targetId}
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        {totalCount > 0 && (
          <div className='mt-4 flex items-center justify-between'>
            <p className='text-sm text-muted-foreground'>
              {totalCount} entries (page {page} of {totalPages})
            </p>
            <div className='flex gap-2'>
              <Button
                variant='outline'
                size='sm'
                disabled={page <= 1}
                onClick={() => setPage((p) => p - 1)}
              >
                Previous
              </Button>
              <Button
                variant='outline'
                size='sm'
                disabled={page >= totalPages}
                onClick={() => setPage((p) => p + 1)}
              >
                Next
              </Button>
            </div>
          </div>
        )}
      </Main>
    </>
  )
}

function formatDateTime(value: string) {
  return new Intl.DateTimeFormat(undefined, {
    dateStyle: 'medium',
    timeStyle: 'short',
  }).format(new Date(value))
}
