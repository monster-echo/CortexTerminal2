import { Area, AreaChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import type { HourlyStatsPoint } from '@/services/console-api'

function formatBytes(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / (1024 * 1024)).toFixed(1)} MB`
  return `${(bytes / (1024 * 1024 * 1024)).toFixed(2)} GB`
}

interface TrafficChartProps {
  data: HourlyStatsPoint[]
}

export function TrafficChart({ data }: TrafficChartProps) {
  const chartData = data.map((point) => ({
    time: new Date(point.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    bytes: point.bytesTransferred,
  }))

  return (
    <ResponsiveContainer width='100%' height={250}>
      <AreaChart data={chartData}>
        <CartesianGrid strokeDasharray='3 3' className='stroke-muted' />
        <XAxis dataKey='time' className='text-xs' tick={{ fontSize: 11 }} />
        <YAxis className='text-xs' tick={{ fontSize: 11 }} tickFormatter={formatBytes} />
        <Tooltip
          formatter={(value) => [formatBytes(Number(value)), 'Traffic']}
          contentStyle={{ fontSize: 12 }}
        />
        <Area
          type='monotone'
          dataKey='bytes'
          stroke='#3b82f6'
          fill='#3b82f6'
          fillOpacity={0.15}
          strokeWidth={2}
        />
      </AreaChart>
    </ResponsiveContainer>
  )
}
