import { useMemo } from 'react'
import { useTranslation } from 'react-i18next'
import { useQuery } from '@tanstack/react-query'
import { Link } from '@tanstack/react-router'
import { useAuthStore } from '@/stores/auth-store'
import { useLayout } from '@/context/layout-provider'
import { createConsoleApi, type SessionSummary } from '@/services/console-api'
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
  SidebarRail,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
} from '@/components/ui/sidebar'
import { StatusDot } from '@/components/shared/status-dot'
import { getSidebarData } from './data/sidebar-data'
import { NavGroup } from './nav-group'
import { NavUser } from './nav-user'
import { TeamSwitcher } from './team-switcher'

export function AppSidebar() {
  const { collapsible, variant } = useLayout()
  const { t } = useTranslation()
  const user = useAuthStore((state) => state.auth.user)
  const sidebarData = getSidebarData(t)

  return (
    <Sidebar collapsible={collapsible} variant={variant}>
      <SidebarHeader>
        <TeamSwitcher teams={sidebarData.teams} />
      </SidebarHeader>
      <SidebarContent>
        {sidebarData.navGroups.map((props) => (
          <NavGroup key={props.title} {...props} />
        ))}
        <RecentSessionsGroup />
      </SidebarContent>
      <SidebarFooter>
        <NavUser
          user={{
            name: user?.username ?? sidebarData.user.name,
            email: user?.email ?? (user?.username
              ? `${user.username}@gateway.local`
              : sidebarData.user.email),
            avatar: sidebarData.user.avatar,
          }}
        />
      </SidebarFooter>
      <SidebarRail />
    </Sidebar>
  )
}

function RecentSessionsGroup() {
  const { t } = useTranslation()
  const api = useMemo(() => createConsoleApi({
    getToken: () => useAuthStore.getState().auth.accessToken,
    onUnauthorized: () => useAuthStore.getState().auth.reset(),
    onTokenRefreshed: (newToken: string) =>
      useAuthStore.getState().auth.setAccessToken(newToken),
  }), [])

  const { data: sessions } = useQuery({
    queryKey: ['sidebar-recent-sessions'],
    queryFn: () => api.listSessions(),
    staleTime: 30_000,
  })

  const recentSessions = sessions?.slice(0, 5)

  if (!recentSessions || recentSessions.length === 0) {
    return null
  }

  return (
    <SidebarGroup>
      <SidebarGroupLabel>{t('nav.recentSessions')}</SidebarGroupLabel>
      <SidebarMenu>
        {recentSessions.map((session: SessionSummary) => (
          <SidebarMenuItem key={session.sessionId}>
            <SidebarMenuButton asChild tooltip={session.sessionId.slice(0, 8)}>
              <Link
                to='/sessions/$sessionId'
                params={{ sessionId: session.sessionId }}
              >
                <StatusDot status={session.status} />
                <span className='truncate font-mono text-xs'>
                  {session.sessionId.slice(0, 8)}
                </span>
              </Link>
            </SidebarMenuButton>
          </SidebarMenuItem>
        ))}
        <SidebarMenuItem>
          <SidebarMenuButton asChild>
            <Link to='/sessions'>
              <span>{t('nav.more')}</span>
            </Link>
          </SidebarMenuButton>
        </SidebarMenuItem>
      </SidebarMenu>
    </SidebarGroup>
  )
}
