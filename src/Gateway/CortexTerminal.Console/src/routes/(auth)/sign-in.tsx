import { z } from 'zod'
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useAuthStore } from '@/stores/auth-store'
import { SignIn } from '@/features/auth/sign-in'

const searchSchema = z.object({
  redirect: z.string().optional(),
  token: z.string().optional(),
  error: z.string().optional(),
})

export const Route = createFileRoute('/(auth)/sign-in')({
  beforeLoad: ({ search }) => {
    // Handle OAuth callback: store token and redirect
    if (search.token) {
      const { auth } = useAuthStore.getState()
      auth.setAccessToken(search.token)
      throw redirect({ to: search.redirect || '/sessions' })
    }

    const accessToken = useAuthStore.getState().auth.accessToken
    if (accessToken) {
      throw redirect({ to: search.redirect || '/sessions' })
    }
  },
  component: SignIn,
  validateSearch: searchSchema,
})
