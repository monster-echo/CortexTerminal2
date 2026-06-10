import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import type { DailyCount } from '@/services/console-api'

const ACTION_COLORS: Record<string, string> = {
  'user.oauth_login': '#3b82f6',
  'user.phone_login': '#22c55e',
  'user.huawei_quick_login': '#f59e0b',
}

const ACTION_LABELS: Record<string, string> = {
  'user.oauth_login': 'OAuth',
  'user.phone_login': 'Phone',
  'user.huawei_quick_login': 'Huawei',
}

interface LoginTrendChartProps {
  data: DailyCount[]
}

export function LoginTrendChart({ data }: LoginTrendChartProps) {
  const dates = [...new Set(data.map((d) => d.date))].sort()
  const actions = [...new Set(data.map((d) => d.action))]

  const chartData = dates.map((date) => {
    const entry: Record<string, string | number> = { date }
    for (const action of actions) {
      const match = data.find((d) => d.date === date && d.action === action)
      entry[ACTION_LABELS[action] ?? action] = match?.count ?? 0
    }
    return entry
  })

  return (
    <ResponsiveContainer width='100%' height={250}>
      <BarChart data={chartData}>
        <CartesianGrid strokeDasharray='3 3' className='stroke-muted' />
        <XAxis dataKey='date' className='text-xs' tick={{ fontSize: 11 }} />
        <YAxis className='text-xs' tick={{ fontSize: 11 }} allowDecimals={false} />
        <Tooltip contentStyle={{ fontSize: 12 }} />
        {actions.map((action) => (
          <Bar
            key={action}
            dataKey={ACTION_LABELS[action] ?? action}
            stackId='a'
            fill={ACTION_COLORS[action] ?? '#6b7280'}
            radius={actions.indexOf(action) === actions.length - 1 ? [4, 4, 0, 0] : undefined}
          />
        ))}
      </BarChart>
    </ResponsiveContainer>
  )
}
