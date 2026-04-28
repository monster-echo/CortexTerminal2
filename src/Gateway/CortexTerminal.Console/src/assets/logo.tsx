import { type SVGProps } from 'react'
import { cn } from '@/lib/utils'

export function Logo({ className, ...props }: SVGProps<SVGSVGElement>) {
  return (
    <svg
      id='cortexterminal-logo'
      viewBox='0 0 1024 1024'
      xmlns='http://www.w3.org/2000/svg'
      height='24'
      width='24'
      fill='none'
      className={cn('size-6', className)}
      {...props}
    >
      <title>CortexTerminal</title>
      <defs>
        <linearGradient id='ct-blue' x1='220' y1='520' x2='450' y2='220' gradientUnits='userSpaceOnUse'>
          <stop offset='0' stopColor='#3BA5F9' />
          <stop offset='1' stopColor='#38E6FF' />
        </linearGradient>
        <linearGradient id='ct-purple' x1='574' y1='804' x2='804' y2='504' gradientUnits='userSpaceOnUse'>
          <stop offset='0' stopColor='#9333EA' />
          <stop offset='1' stopColor='#C084FC' />
        </linearGradient>
      </defs>
      <rect width='1024' height='1024' rx='160' fill='currentColor' opacity='0.1' />
      <path d='M 220 502 V 310 C 220 260.3 260.3 220 310 220 H 502' stroke='url(#ct-blue)' strokeWidth='60' strokeLinecap='round' />
      <path d='M 804 522 V 714 C 804 763.7 763.7 804 714 804 H 522' stroke='url(#ct-purple)' strokeWidth='60' strokeLinecap='round' />
      <path d='M 440 384 L 584 512 L 440 640' stroke='currentColor' strokeWidth='65' strokeLinecap='round' strokeLinejoin='round' />
    </svg>
  )
}
