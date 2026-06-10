import { Cell, Pie, PieChart, ResponsiveContainer, Tooltip } from 'recharts'
import type { ProviderCount } from '@/services/console-api'

const COLORS = ['#3b82f6', '#22c55e', '#f59e0b', '#ef4444', '#8b5cf6']

const PROVIDER_LABELS: Record<string, string> = {
  'user.oauth_login': 'OAuth',
  'user.phone_login': 'Phone',
  'user.huawei_quick_login': 'Huawei',
}

interface AuthProviderChartProps {
  data: ProviderCount[]
}

export function AuthProviderChart({ data }: AuthProviderChartProps) {
  const chartData = data.map((d) => ({
    name: PROVIDER_LABELS[d.provider] ?? d.provider,
    value: d.count,
  }))

  return (
    <div>
      <ResponsiveContainer width='100%' height={200}>
        <PieChart>
          <Pie
            data={chartData}
            cx='50%'
            cy='50%'
            innerRadius={50}
            outerRadius={80}
            paddingAngle={4}
            dataKey='value'
          >
            {chartData.map((_, index) => (
              <Cell key={`cell-${index}`} fill={COLORS[index % COLORS.length]} />
            ))}
          </Pie>
          <Tooltip contentStyle={{ fontSize: 12 }} />
        </PieChart>
      </ResponsiveContainer>
      <div className='flex flex-wrap justify-center gap-3 mt-2'>
        {chartData.map((entry, index) => (
          <div key={entry.name} className='flex items-center gap-1.5 text-xs text-muted-foreground'>
            <div
              className='h-2.5 w-2.5 rounded-full'
              style={{ backgroundColor: COLORS[index % COLORS.length] }}
            />
            {entry.name} ({entry.value})
          </div>
        ))}
      </div>
    </div>
  )
}
