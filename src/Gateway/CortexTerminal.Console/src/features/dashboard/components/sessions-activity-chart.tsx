import { Bar, BarChart, CartesianGrid, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import type { HourlyStatsPoint } from '@/services/console-api'

interface SessionsActivityChartProps {
  data: HourlyStatsPoint[]
}

export function SessionsActivityChart({ data }: SessionsActivityChartProps) {
  const chartData = data.map((point) => ({
    time: new Date(point.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    sessions: point.activeSessions,
  }))

  return (
    <ResponsiveContainer width='100%' height={250}>
      <BarChart data={chartData}>
        <CartesianGrid strokeDasharray='3 3' className='stroke-muted' />
        <XAxis dataKey='time' className='text-xs' tick={{ fontSize: 11 }} />
        <YAxis className='text-xs' tick={{ fontSize: 11 }} allowDecimals={false} />
        <Tooltip contentStyle={{ fontSize: 12 }} />
        <Bar dataKey='sessions' fill='#f59e0b' radius={[4, 4, 0, 0]} name='Active Sessions' />
      </BarChart>
    </ResponsiveContainer>
  )
}
