import { CartesianGrid, Legend, Line, LineChart, ResponsiveContainer, Tooltip, XAxis, YAxis } from 'recharts'
import type { HourlyStatsPoint } from '@/services/console-api'

interface ConnectionsChartProps {
  data: HourlyStatsPoint[]
}

export function ConnectionsChart({ data }: ConnectionsChartProps) {
  const chartData = data.map((point) => ({
    time: new Date(point.timestamp).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
    clients: point.connectedClients,
    workers: point.onlineWorkers,
  }))

  return (
    <ResponsiveContainer width='100%' height={250}>
      <LineChart data={chartData}>
        <CartesianGrid strokeDasharray='3 3' className='stroke-muted' />
        <XAxis dataKey='time' className='text-xs' tick={{ fontSize: 11 }} />
        <YAxis className='text-xs' tick={{ fontSize: 11 }} allowDecimals={false} />
        <Tooltip contentStyle={{ fontSize: 12 }} />
        <Legend wrapperStyle={{ fontSize: 12 }} />
        <Line type='monotone' dataKey='clients' stroke='#8b5cf6' strokeWidth={2} dot={false} name='Clients' />
        <Line type='monotone' dataKey='workers' stroke='#22c55e' strokeWidth={2} dot={false} name='Workers' />
      </LineChart>
    </ResponsiveContainer>
  )
}
