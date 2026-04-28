import { Shield, UserCheck } from 'lucide-react'
import { type UserStatus } from './schema'

export const statusColors = new Map<UserStatus, string>([
  ['active', 'bg-teal-100/30 text-teal-900 dark:text-teal-200 border-teal-200'],
  ['disabled', 'bg-neutral-300/40 border-neutral-300'],
])

export const roles = [
  {
    label: 'Admin',
    value: 'admin',
    icon: Shield,
  },
  {
    label: 'User',
    value: 'user',
    icon: UserCheck,
  },
] as const
