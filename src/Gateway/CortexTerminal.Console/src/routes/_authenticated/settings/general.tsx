import { createFileRoute } from '@tanstack/react-router'
import { SettingsGeneral } from '@/features/settings/appearance'

export const Route = createFileRoute('/_authenticated/settings/general')({
  component: SettingsGeneral,
})
