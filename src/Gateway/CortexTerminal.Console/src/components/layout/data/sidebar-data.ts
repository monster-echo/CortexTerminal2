import { type TFunction } from 'i18next'
import {
  LayoutDashboard,
  Terminal,
  Server,
  Users,
  Settings,
  FileText,
  Globe,
} from 'lucide-react'
import { Logo } from '@/assets/logo'
import { type SidebarData } from '../types'

export function getSidebarData(t: TFunction): SidebarData {
  return {
    user: {
      name: '',
      email: '',
      avatar: '',
    },
    teams: [
      {
        name: t('brand.name'),
        logo: Logo,
        plan: t('common.gatewayConsole'),
      },
    ],
    navGroups: [
      {
        title: t('nav.groups.overview'),
        items: [
          { title: t('nav.dashboard'), icon: LayoutDashboard, url: '/dashboard' },
          {
            title: t('nav.homepage'),
            icon: Globe,
            url: 'https://monster-echo.github.io/CortexTerminal/',
          },
        ],
      },
      {
        title: t('nav.groups.terminal'),
        items: [
          { title: t('nav.sessions'), icon: Terminal, url: '/sessions' },
        ],
      },
      {
        title: t('nav.groups.infrastructure'),
        items: [
          { title: t('nav.workers'), icon: Server, url: '/workers' },
        ],
      },
      {
        title: t('nav.groups.admin'),
        items: [
          { title: t('nav.users'), icon: Users, url: '/users' },
        ],
      },
      {
        title: t('nav.groups.system'),
        items: [
          { title: t('nav.settings'), icon: Settings, url: '/settings' },
          { title: t('nav.auditLog'), icon: FileText, url: '/audit-log' },
        ],
      },
    ],
  }
}
