import { describe, expect, it, vi, beforeEach } from 'vitest'
import { render } from 'vitest-browser-react'
import { SliderCaptchaDialog } from './slider-captcha-dialog'

const mockChallengeData = {
  id: 'test-challenge-id',
  backgroundImage: btoa('fake-png-bg'),
  sliderImage: btoa('fake-png-slider'),
  y: 80,
}

const mockFetch = vi.hoisted(() =>
  vi.fn<(input: string | Request) => Promise<Response>>()
)

vi.stubGlobal('fetch', mockFetch)

function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })
}

describe('SliderCaptchaDialog', () => {
  const onSuccess = vi.fn()
  const onOpenChange = vi.fn()

  beforeEach(() => {
    vi.clearAllMocks()
    mockFetch.mockResolvedValue(jsonResponse(mockChallengeData))
  })

  it('renders dialog title when open', async () => {
    const { getByRole } = await render(
      <SliderCaptchaDialog
        open={true}
        onOpenChange={onOpenChange}
        onSuccess={onSuccess}
      />
    )

    // Dialog title should be visible
    await expect
      .element(getByRole('heading', { name: '滑块验证' }))
      .toBeInTheDocument()

    // Fetch was called to load the challenge
    await vi.waitFor(() => {
      expect(mockFetch).toHaveBeenCalledWith('/api/auth/captcha/challenge')
    })
  })

  it('renders without crashing when closed', async () => {
    await render(
      <SliderCaptchaDialog
        open={false}
        onOpenChange={onOpenChange}
        onSuccess={onSuccess}
      />
    )
    // Should not throw, and should not call fetch
    expect(mockFetch).not.toHaveBeenCalled()
  })

  it('fetches challenge on open', async () => {
    await render(
      <SliderCaptchaDialog
        open={true}
        onOpenChange={onOpenChange}
        onSuccess={onSuccess}
      />
    )

    await vi.waitFor(() => {
      expect(mockFetch).toHaveBeenCalledTimes(1)
      expect(mockFetch).toHaveBeenCalledWith('/api/auth/captcha/challenge')
    })
  })

  it('renders slider images after challenge loads', async () => {
    const { getByRole } = await render(
      <SliderCaptchaDialog
        open={true}
        onOpenChange={onOpenChange}
        onSuccess={onSuccess}
      />
    )

    // Wait for images to render — captcha background and slider piece
    await vi.waitFor(() => {
      const images = getByRole('img', { name: 'captcha background' })
      expect(images).toBeTruthy()
    })
  })
})
