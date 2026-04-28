export type UserRole = 'admin' | 'user'
export type UserStatus = 'active' | 'disabled'

export interface User {
  id: string
  name: string
  email: string
  role: UserRole
  status: UserStatus
  avatarUrl?: string
}
