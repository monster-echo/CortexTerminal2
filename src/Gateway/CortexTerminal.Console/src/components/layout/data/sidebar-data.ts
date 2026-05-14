import { type TFunction } from 'i18next'
import {
  LayoutDashboard,
  Server,
  Users,
  Settings,
  FileText,
  Globe,
} from 'lucide-react'
import { Logo } from '@/assets/logo'
import { type SidebarData } from '../types'

export function getSidebarData(t: TFunction, role?: string): SidebarData {
  const isAdmin = role === 'admin'

  const navGroups = [
    {
      title: t('nav.groups.overview'),
      items: [
        { title: t('nav.dashboard'), icon: LayoutDashboard, url: '/dashboard' },
        {
          title: t('nav.homepage'),
          icon: Globe,
          url: '/',
        },
      ],
    },
    {
      title: t('nav.groups.infrastructure'),
      items: [
        { title: t('nav.workers'), icon: Server, url: '/workers' },
      ],
    },
    ...(isAdmin
      ? [{
          title: t('nav.groups.admin'),
          items: [
            { title: t('nav.users'), icon: Users, url: '/users' },
          ],
        }]
      : []),
    {
      title: t('nav.groups.system'),
      items: [
        { title: t('nav.settings'), icon: Settings, url: '/settings' },
        ...(isAdmin
          ? [{ title: t('nav.auditLog'), icon: FileText, url: '/audit-log' }]
          : []),
      ],
    },
  ]

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
    navGroups,
  }
}
