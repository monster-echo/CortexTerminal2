import { useQuery } from '@tanstack/react-query'
import { createConsoleApi } from '@/services/console-api'
import { useTranslation } from 'react-i18next'
import { useAuthStore } from '@/stores/auth-store'
import { Header } from '@/components/layout/header'
import { LanguageSwitcher } from '@/components/layout/language-switcher'
import { Main } from '@/components/layout/main'
import { ProfileDropdown } from '@/components/profile-dropdown'
import { ThemeSwitch } from '@/components/theme-switch'
import { UsersDialogs } from './components/users-dialogs'
// import { UsersPrimaryButtons } from './components/users-primary-buttons'
import { UsersProvider } from './components/users-provider'
import { UsersTable } from './components/users-table'

const consoleApi = createConsoleApi({
  getToken: () => useAuthStore.getState().auth.accessToken,
  onUnauthorized: () => useAuthStore.getState().auth.reset(),
  onTokenRefreshed: (newToken) =>
    useAuthStore.getState().auth.setAccessToken(newToken),
})

export function Users() {
  const { t } = useTranslation()
  const { data: users = [], isLoading } = useQuery({
    queryKey: ['users'],
    queryFn: () => consoleApi.listUsers(),
  })

  return (
    <UsersProvider>
      <Header fixed>
        <LanguageSwitcher />
        <ThemeSwitch />
        <ProfileDropdown />
      </Header>
      <Main className='flex flex-1 flex-col gap-4 sm:gap-6'>
        <div className='flex flex-wrap items-end justify-between gap-2'>
          <div>
            <h2 className='text-2xl font-bold tracking-tight'>
              {t('users.title')}
            </h2>
            <p className='text-muted-foreground'>
              Manage users and their roles.
            </p>
          </div>
          {/* <UsersPrimaryButtons /> */}
        </div>
        {isLoading ? (
          <div className='text-muted-foreground'>{t('common.loading')}</div>
        ) : (
          <UsersTable data={users} />
        )}
      </Main>
      <UsersDialogs />
    </UsersProvider>
  )
}
