import { useState } from 'react'
import { useTranslation } from 'react-i18next'
import { cn } from '@/lib/utils'

export function InstallCommand({ className }: { className?: string }) {
  const { t } = useTranslation()
  const [activeTab, setActiveTab] = useState<'sh' | 'ps1'>('sh')
  const [copied, setCopied] = useState(false)

  const commands: Record<'sh' | 'ps1', { prompt: string; cmd: string }> = {
    sh: { prompt: '$', cmd: t('landing.installCmdBash') },
    ps1: { prompt: '>', cmd: t('landing.installCmdPs1') },
  }

  const { prompt, cmd } = commands[activeTab]

  function handleCopy() {
    navigator.clipboard.writeText(cmd).then(() => {
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    })
  }

  return (
    <div className={cn('max-w-[640px] mx-auto', className)}>
      <div className="flex justify-center gap-1 mb-3">
        <button
          className={cn(
            'px-3.5 py-1.5 rounded-md text-xs font-mono border transition-all',
            activeTab === 'sh'
              ? 'bg-emerald-500/15 text-emerald-500 border-emerald-500'
              : 'bg-[#242429] text-[#71717a] border-[#2e2e36] hover:text-[#a1a1aa]'
          )}
          onClick={() => setActiveTab('sh')}
        >
          {t('landing.tabBash')}
        </button>
        <button
          className={cn(
            'px-3.5 py-1.5 rounded-md text-xs font-mono border transition-all',
            activeTab === 'ps1'
              ? 'bg-emerald-500/15 text-emerald-500 border-emerald-500'
              : 'bg-[#242429] text-[#71717a] border-[#2e2e36] hover:text-[#a1a1aa]'
          )}
          onClick={() => setActiveTab('ps1')}
        >
          {t('landing.tabPowershell')}
        </button>
      </div>
      <div className="bg-[#121214] border border-[#2e2e36] rounded-xl overflow-hidden relative">
        {/* Gradient border overlay */}
        <div
          className="absolute inset-0 rounded-xl pointer-events-none"
          style={{
            background:
              'linear-gradient(135deg, rgba(16,185,129,0.3), rgba(6,182,212,0.1))',
            mask: 'linear-gradient(#fff 0 0) content-box, linear-gradient(#fff 0 0)',
            maskComposite: 'exclude',
            WebkitMaskComposite: 'xor',
            padding: '1px',
          }}
        />
        <div className="flex items-center justify-between px-4 py-2.5 bg-[#1a1a1d] border-b border-[#2e2e36]">
          <div className="flex gap-1.5">
            <span className="w-2.5 h-2.5 rounded-full bg-red-500" />
            <span className="w-2.5 h-2.5 rounded-full bg-amber-500" />
            <span className="w-2.5 h-2.5 rounded-full bg-emerald-500" />
          </div>
          <span className="text-xs text-[#71717a] font-mono">terminal</span>
          <span className="w-[52px]" />
        </div>
        <div className="px-5 py-4 bg-[#0a0a0b] flex items-center gap-3">
          <span className="text-emerald-500 font-mono text-sm select-none shrink-0">
            {prompt}
          </span>
          <code className="font-mono text-sm text-[#e4e4e7] flex-1 break-all">
            {cmd}
          </code>
          <button
            className={cn(
              'shrink-0 px-3 py-1.5 rounded-md text-xs font-sans border transition-all whitespace-nowrap cursor-pointer',
              copied
                ? 'bg-emerald-500/15 text-emerald-500 border-emerald-500'
                : 'bg-[#242429] border-[#2e2e36] text-[#a1a1aa] hover:bg-[#1a1a1d] hover:text-[#e4e4e7] hover:border-emerald-500'
            )}
            onClick={handleCopy}
          >
            {copied ? t('landing.btnCopied') : t('landing.btnCopy')}
          </button>
        </div>
      </div>
    </div>
  )
}
