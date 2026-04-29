import { useState } from 'react'
import { useQuery, useQueryClient, useMutation } from '@tanstack/react-query'
import { useTranslation, Trans } from 'react-i18next'
import { useNavigate } from '@tanstack/react-router'
import { formatDistanceToNow } from 'date-fns'
import { ArrowUpCircle, Loader2, Server } from 'lucide-react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import {
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
} from '@/components/ui/table'
import { StatusDot } from '@/components/shared/status-dot'
import { StatusBadge } from '@/components/shared/status-badge'
import { Header } from '@/components/layout/header'
import { Main } from '@/components/layout/main'
import { ConfirmDialog } from '@/components/confirm-dialog'
import { useWorkers } from '@/hooks/use-workers'
import { getApi } from '@/lib/api'

export function WorkerListPage() {
  const { t } = useTranslation()
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const api = getApi()

  const [upgradeTarget, setUpgradeTarget] = useState<{
    workerId: string
    workerName: string
    currentVersion: string
    targetVersion: string
  } | null>(null)

  const workersQuery = useWorkers()

  const gatewayInfoQuery = useQuery({
    queryKey: ['gateway-info', api],
    queryFn: () => api.getGatewayInfo(),
  })

  const workers = workersQuery.data ?? []

  const upgradeMutation = useMutation({
    mutationFn: () => {
      if (!upgradeTarget) throw new Error('No target')
      return api.upgradeWorker(upgradeTarget.workerId)
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['workers'] })
      setUpgradeTarget(null)
    },
  })

  const handleUpgradeClick = (
    e: React.MouseEvent,
    worker: { workerId: string; name?: string; version?: string }
  ) => {
    e.stopPropagation()
    if (!worker.version || !gatewayInfoQuery.data?.latestWorkerVersion) return
    setUpgradeTarget({
      workerId: worker.workerId,
      workerName: worker.name ?? worker.workerId,
      currentVersion: worker.version,
      targetVersion: gatewayInfoQuery.data.latestWorkerVersion,
    })
  }

  return (
    <>
      <Header>
        <div>
          <p className='text-sm font-medium text-muted-foreground'>
            {t('workers.gatewayConsole')}
          </p>
          <h1 className='text-lg font-semibold'>{t('workers.title')}</h1>
        </div>
      </Header>

      <Main>
        <div className='mb-6'>
          <h2 className='text-2xl font-bold tracking-tight'>
            {t('workers.title')}
          </h2>
          <p className='text-muted-foreground'>
            {t('workers.description', 'Monitor connected worker nodes and their sessions.')}
          </p>
        </div>

        <Card>
          <CardHeader>
            <CardTitle>{t('workers.title')}</CardTitle>
          </CardHeader>
          <CardContent>
            {workersQuery.isLoading ? (
              <div className='flex items-center gap-2 text-sm text-muted-foreground'>
                <Loader2 className='size-4 animate-spin' /> {t('common.loading')}
              </div>
            ) : workersQuery.isError ? (
              <p className='text-sm text-destructive'>
                {workersQuery.error instanceof Error
                  ? workersQuery.error.message
                  : t('common.error')}
              </p>
            ) : workers.length === 0 ? (
              <div className='rounded-lg border border-dashed p-10 text-center'>
                <Server className='mx-auto mb-3 size-8 text-muted-foreground' />
                <h3 className='text-lg font-semibold'>
                  {t('workers.emptyTitle', 'No workers connected')}
                </h3>
                <p className='mt-1 text-sm text-muted-foreground'>
                  {t('workers.emptyDescription', 'Workers will appear here when they connect to the gateway.')}
                </p>
              </div>
            ) : (
              <Table>
                <TableHeader>
                  <TableRow>
                    <TableHead>{t('workers.status._label', 'Status')}</TableHead>
                    <TableHead>{t('workers.workerId', 'Worker ID')}</TableHead>
                    <TableHead>{t('workers.version')}</TableHead>
                    <TableHead>{t('workers.address')}</TableHead>
                    <TableHead>{t('workers.sessionsColumn', 'Sessions')}</TableHead>
                    <TableHead>{t('workers.uptime')}</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {workers.map((worker) => {
                    const status = worker.isOnline ? 'online' : 'offline'
                    const statusLabel = worker.isOnline
                      ? t('workers.status.online')
                      : t('workers.status.offline')
                    const hasUpgrade =
                      gatewayInfoQuery.data?.latestWorkerVersion &&
                      worker.version &&
                      worker.version !== gatewayInfoQuery.data.latestWorkerVersion

                    return (
                      <TableRow
                        key={worker.workerId}
                        className='cursor-pointer'
                        onClick={() =>
                          navigate({
                            to: '/workers/$workerId',
                            params: { workerId: worker.workerId },
                          })
                        }
                      >
                        <TableCell>
                          <div className='flex items-center gap-2'>
                            <StatusDot status={status} />
                            <StatusBadge status={status} label={statusLabel} />
                          </div>
                        </TableCell>
                        <TableCell className='font-mono text-xs sm:text-sm'>
                          {worker.name ?? worker.workerId}
                        </TableCell>
                        <TableCell>
                          <div className='flex items-center gap-1.5'>
                            <span className='font-mono text-xs'>
                              {worker.version ?? '—'}
                            </span>
                            {hasUpgrade && (
                              <ArrowUpCircle
                                className='size-3.5 cursor-pointer text-amber-500 hover:text-amber-600'
                                onClick={(e) => handleUpgradeClick(e, worker)}
                              />
                            )}
                          </div>
                        </TableCell>
                        <TableCell className='font-mono text-xs'>
                          {worker.address ?? '\u2014'}
                        </TableCell>
                        <TableCell>
                          {t('workers.sessions', { count: worker.sessionCount })}
                        </TableCell>
                        <TableCell>
                          {worker.connectedAt
                            ? formatDistanceToNow(new Date(worker.connectedAt), {
                                addSuffix: true,
                              })
                            : '\u2014'}
                        </TableCell>
                      </TableRow>
                    )
                  })}
                </TableBody>
              </Table>
            )}
          </CardContent>
        </Card>

        <ConfirmDialog
          open={upgradeTarget !== null}
          onOpenChange={(open) => {
            if (!open) setUpgradeTarget(null)
          }}
          title={t('workers.upgrade.title')}
          desc={
            upgradeTarget ? (
              <Trans
                i18nKey="workers.upgrade.description"
                values={{
                  workerName: upgradeTarget.workerName,
                  currentVersion: upgradeTarget.currentVersion,
                  targetVersion: upgradeTarget.targetVersion,
                }}
                components={{ strong: <strong />, code: <code /> }}
              />
            ) : (
              ''
            )
          }
          confirmText={t('workers.upgrade.button')}
          destructive
          isLoading={upgradeMutation.isPending}
          handleConfirm={() => upgradeMutation.mutate()}
        />
      </Main>
    </>
  )
}
