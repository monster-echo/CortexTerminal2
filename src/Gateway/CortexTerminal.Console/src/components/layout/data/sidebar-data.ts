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

export const sidebarData: SidebarData = {
  user: {
    name: '',
    email: '',
    avatar: '',
  },
  teams: [
    {
      name: 'CortexTerminal',
      logo: Logo,
      plan: 'Gateway',
    },
  ],
  navGroups: [
    {
      title: 'Overview',
      items: [
        { title: 'Dashboard', icon: LayoutDashboard, url: '/dashboard' },
        {
          title: 'Homepage',
          icon: Globe,
          url: 'https://monster-echo.github.io/CortexTerminal/',
        },
      ],
    },
    {
      title: 'Terminal',
      items: [
        { title: 'Sessions', icon: Terminal, url: '/sessions' },
      ],
    },
    {
      title: 'Infrastructure',
      items: [
        { title: 'Workers', icon: Server, url: '/workers' },
      ],
    },
    {
      title: 'Admin',
      items: [
        { title: 'Users', icon: Users, url: '/users' },
      ],
    },
    {
      title: 'System',
      items: [
        { title: 'Settings', icon: Settings, url: '/settings' },
        { title: 'Audit Log', icon: FileText, url: '/audit-log' },
      ],
    },
  ],
}
