import { useState, useRef, useCallback, useEffect } from 'react'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'

interface SliderCaptchaDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  onSuccess: (captchaToken: string) => void
}

interface CaptchaChallenge {
  id: string
  backgroundImage: string
  sliderImage: string
  y: number
}

const IMAGE_WIDTH = 300
const PIECE_SIZE = 44

export function SliderCaptchaDialog({
  open,
  onOpenChange,
  onSuccess,
}: SliderCaptchaDialogProps) {
  const [challenge, setChallenge] = useState<CaptchaChallenge | null>(null)
  const [sliderX, setSliderX] = useState(0)
  const [dragging, setDragging] = useState(false)
  const [verifying, setVerifying] = useState(false)
  const [failed, setFailed] = useState(false)
  const trackRef = useRef<HTMLDivElement>(null)
  const dragStartX = useRef(0)
  const sliderStartX = useRef(0)

  const loadChallenge = useCallback(async () => {
    setFailed(false)
    setSliderX(0)
    try {
      const res = await fetch('/api/auth/captcha/challenge')
      if (!res.ok) return
      const data = await res.json()
      setChallenge(data)
    } catch {
      // network error
    }
  }, [])

  useEffect(() => {
    if (open) loadChallenge()
  }, [open, loadChallenge])

  const handleDragStart = useCallback(
    (e: React.MouseEvent | React.TouchEvent) => {
      if (verifying) return
      e.preventDefault()
      setDragging(true)
      setFailed(false)
      const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX
      dragStartX.current = clientX
      sliderStartX.current = sliderX
    },
    [verifying, sliderX]
  )

  useEffect(() => {
    if (!dragging) return

    const handleMove = (e: MouseEvent | TouchEvent) => {
      const clientX = 'touches' in e ? e.touches[0].clientX : e.clientX
      const delta = clientX - dragStartX.current
      const maxX = IMAGE_WIDTH - PIECE_SIZE
      const newX = Math.max(0, Math.min(maxX, sliderStartX.current + delta))
      setSliderX(newX)
    }

    const handleEnd = async () => {
      setDragging(false)
      if (!challenge) return
      setVerifying(true)
      try {
        const res = await fetch('/api/auth/captcha/verify', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id: challenge.id, x: Math.round(sliderX) }),
        })
        if (!res.ok) {
          setFailed(true)
          setSliderX(0)
          loadChallenge()
          return
        }
        const data = await res.json()
        onSuccess(data.captchaToken)
        onOpenChange(false)
      } catch {
        setFailed(true)
        loadChallenge()
      } finally {
        setVerifying(false)
      }
    }

    window.addEventListener('mousemove', handleMove)
    window.addEventListener('mouseup', handleEnd)
    window.addEventListener('touchmove', handleMove, { passive: false })
    window.addEventListener('touchend', handleEnd)
    return () => {
      window.removeEventListener('mousemove', handleMove)
      window.removeEventListener('mouseup', handleEnd)
      window.removeEventListener('touchmove', handleMove)
      window.removeEventListener('touchend', handleEnd)
    }
  }, [dragging, challenge, sliderX, onSuccess, onOpenChange, loadChallenge])

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[360px]">
        <DialogHeader>
          <DialogTitle>滑块验证</DialogTitle>
        </DialogHeader>
        {challenge && (
          <div className="flex flex-col items-center gap-3">
            {/* Captcha image area */}
            <div
              className="relative select-none overflow-hidden rounded-md border"
              style={{ width: IMAGE_WIDTH, height: 180 }}
            >
              {/* Background with hole */}
              <img
                src={`data:image/png;base64,${challenge.backgroundImage}`}
                alt="captcha background"
                className="block"
                draggable={false}
                width={IMAGE_WIDTH}
                height={180}
              />
              {/* Slider piece overlay */}
              <img
                src={`data:image/png;base64,${challenge.sliderImage}`}
                alt="captcha slider"
                className="absolute top-0 left-0 block"
                draggable={false}
                width={IMAGE_WIDTH}
                height={180}
                style={{
                  transform: `translateX(${sliderX}px)`,
                }}
              />
            </div>

            {/* Slider track */}
            <div
              ref={trackRef}
              className="relative h-10 w-full rounded-full bg-muted"
              style={{ width: IMAGE_WIDTH }}
            >
              {/* Filled portion */}
              <div
                className="absolute inset-y-0 left-0 rounded-full bg-primary/20"
                style={{ width: sliderX + PIECE_SIZE }}
              />
              {/* Draggable handle */}
              <div
                className="absolute top-0 flex h-10 w-[44px] cursor-grab items-center justify-center rounded-full border-2 border-primary bg-background shadow active:cursor-grabbing"
                style={{ left: sliderX }}
                onMouseDown={handleDragStart}
                onTouchStart={handleDragStart}
              >
                <svg
                  width="20"
                  height="20"
                  viewBox="0 0 20 20"
                  fill="none"
                  className="text-primary"
                >
                  <path
                    d="M7 4l-4 6 4 6M13 4l4 6-4 6"
                    stroke="currentColor"
                    strokeWidth="2"
                    strokeLinecap="round"
                    strokeLinejoin="round"
                  />
                </svg>
              </div>
            </div>

            {failed && (
              <p className="text-sm text-destructive">验证失败，请重试</p>
            )}
            {verifying && (
              <p className="text-sm text-muted-foreground">验证中...</p>
            )}
          </div>
        )}
      </DialogContent>
    </Dialog>
  )
}
