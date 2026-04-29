import { useEffect, useState } from 'react'
import { Loader2 } from 'lucide-react'
import { cn } from '@/lib/utils'
import type { WorkerSummary } from '@/services/console-api'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Badge } from '@/components/ui/badge'
import { RadioGroup, RadioGroupItem } from '@/components/ui/radio-group'
import { Label } from '@/components/ui/label'

interface NewSessionDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  workers: WorkerSummary[]
  isLoadingWorkers: boolean
  onCreateSession: (workerId?: string) => void
  isCreating: boolean
}

function OsBadge({ os }: { os?: string }) {
  if (!os) return null
  const label = os.includes('Linux')
    ? 'Linux'
    : os.includes('Darwin') || os.includes('macOS')
      ? 'macOS'
      : os.includes('Windows')
        ? 'Windows'
        : os.split(' ')[0]
  return <Badge variant="secondary">{label}</Badge>
}

export function NewSessionDialog({
  open,
  onOpenChange,
  workers,
  isLoadingWorkers,
  onCreateSession,
  isCreating,
}: NewSessionDialogProps) {
  const [selectedWorker, setSelectedWorker] = useState<string>('__auto__')

  useEffect(() => {
    if (open) {
      setSelectedWorker('__auto__')
    }
  }, [open])

  const onlineWorkers = workers.filter((w) => w.isOnline)

  function handleCreate() {
    onCreateSession(selectedWorker === '__auto__' ? undefined : selectedWorker)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[425px]">
        <DialogHeader>
          <DialogTitle>New Session</DialogTitle>
          <DialogDescription>
            Select a worker to run your terminal session, or auto-select.
          </DialogDescription>
        </DialogHeader>

        <div className="py-4">
          {isLoadingWorkers ? (
            <div className="flex items-center justify-center py-8">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : onlineWorkers.length === 0 ? (
            <p className="text-center text-sm text-muted-foreground py-8">
              No workers available.
            </p>
          ) : (
            <RadioGroup
              value={selectedWorker}
              onValueChange={setSelectedWorker}
              className="gap-2"
            >
              {/* Auto-select option */}
              <Label
                htmlFor="worker-auto"
                className={cn(
                  'flex items-center gap-3 rounded-lg border p-3 cursor-pointer transition-colors',
                  'hover:bg-accent/50',
                  selectedWorker === '__auto__' && 'border-primary bg-accent/30'
                )}
              >
                <RadioGroupItem value="__auto__" id="worker-auto" />
                <div className="flex-1">
                  <div className="font-medium text-sm">Auto-select</div>
                  <div className="text-xs text-muted-foreground">
                    Pick the first available worker
                  </div>
                </div>
              </Label>

              {onlineWorkers.map((worker) => (
                <Label
                  key={worker.workerId}
                  htmlFor={`worker-${worker.workerId}`}
                  className={cn(
                    'flex items-center gap-3 rounded-lg border p-3 cursor-pointer transition-colors',
                    'hover:bg-accent/50',
                    selectedWorker === worker.workerId &&
                      'border-primary bg-accent/30'
                  )}
                >
                  <RadioGroupItem
                    value={worker.workerId}
                    id={`worker-${worker.workerId}`}
                  />
                  <div className="flex-1 min-w-0">
                    <div className="flex items-center gap-2">
                      <span className="font-medium text-sm truncate">
                        {worker.hostname || worker.name || worker.workerId}
                      </span>
                      <OsBadge os={worker.operatingSystem} />
                      {worker.architecture && (
                        <Badge variant="outline" className="text-[10px] px-1.5">
                          {worker.architecture}
                        </Badge>
                      )}
                    </div>
                    <div className="text-xs text-muted-foreground truncate">
                      {worker.workerId}
                    </div>
                  </div>
                </Label>
              ))}
            </RadioGroup>
          )}
        </div>

        <DialogFooter>
          <Button
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={isCreating}
          >
            Cancel
          </Button>
          <Button
            onClick={handleCreate}
            disabled={isCreating || isLoadingWorkers || onlineWorkers.length === 0}
          >
            {isCreating && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
            Create Session
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
