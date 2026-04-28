import { z } from 'zod'
import { createFileRoute, redirect } from '@tanstack/react-router'
import { useAuthStore } from '@/stores/auth-store'
import { SignIn } from '@/features/auth/sign-in'

const searchSchema = z.object({
  redirect: z.string().optional(),
})

export const Route = createFileRoute('/(auth)/sign-in')({
  beforeLoad: ({ search }) => {
    const accessToken = useAuthStore.getState().auth.accessToken
    if (accessToken) {
      throw redirect({ to: search.redirect || '/sessions' })
    }
  },
  component: SignIn,
  validateSearch: searchSchema,
})
