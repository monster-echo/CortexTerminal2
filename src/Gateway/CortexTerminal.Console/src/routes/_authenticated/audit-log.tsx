import { createFileRoute } from '@tanstack/react-router'
import { AuditLogPage } from '@/features/audit-log'

export const Route = createFileRoute('/_authenticated/audit-log')({
  component: AuditLogPage,
})
