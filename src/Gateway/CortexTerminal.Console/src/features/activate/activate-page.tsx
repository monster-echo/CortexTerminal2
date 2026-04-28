import { useState } from 'react'
import { useNavigate } from '@tanstack/react-router'
import { createConsoleApi } from '@/services/console-api'
import { useAuthStore } from '@/stores/auth-store'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card'
import { toast } from 'sonner'

const consoleApi = createConsoleApi({
  getToken: () => useAuthStore.getState().auth.accessToken,
  onUnauthorized: () => {
    useAuthStore.getState().auth.reset()
  },
})

export function ActivatePage() {
  const [userCode, setUserCode] = useState('')
  const [loading, setLoading] = useState(false)
  const [confirmed, setConfirmed] = useState(false)
  const navigate = useNavigate()

  async function handleConfirm() {
    if (!userCode.trim()) return
    setLoading(true)
    try {
      await consoleApi.verifyDeviceCode(userCode.trim().toUpperCase())
      setConfirmed(true)
      toast.success('Worker authorized successfully!')
    } catch (error) {
      if (error instanceof Error && 'status' in error && (error as any).status === 401) {
        navigate({ to: '/sign-in', search: { redirect: '/activate' } })
        return
      }
      const message = error instanceof Error ? error.message : 'Verification failed.'
      toast.error(message)
    } finally {
      setLoading(false)
    }
  }

  if (confirmed) {
    return (
      <div className="flex min-h-svh items-center justify-center p-4">
        <Card className="w-full max-w-md">
          <CardHeader className="text-center">
            <CardTitle className="text-2xl">Worker Authorized</CardTitle>
            <CardDescription>
              Your worker has been successfully linked to your account.
            </CardDescription>
          </CardHeader>
          <CardContent className="flex justify-center">
            <Button onClick={() => navigate({ to: '/dashboard' })}>
              Go to Dashboard
            </Button>
          </CardContent>
        </Card>
      </div>
    )
  }

  return (
    <div className="flex min-h-svh items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="text-center">
          <CardTitle className="text-2xl">Activate Worker</CardTitle>
          <CardDescription>
            Enter the code displayed on your worker terminal to authorize it.
          </CardDescription>
        </CardHeader>
        <CardContent>
          <div className="grid gap-4">
            <Input
              placeholder="XXXX-YYYY"
              value={userCode}
              onChange={(e) => setUserCode(e.target.value.toUpperCase())}
              maxLength={9}
              className="text-center text-2xl tracking-widest font-mono h-14"
              onKeyDown={(e) => e.key === 'Enter' && handleConfirm()}
            />
            <Button onClick={handleConfirm} disabled={loading || !userCode.trim()} className="w-full">
              {loading ? 'Verifying...' : 'Authorize Worker'}
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}
