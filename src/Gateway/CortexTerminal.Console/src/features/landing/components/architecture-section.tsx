import { useTranslation } from 'react-i18next'

export function ArchitectureSection() {
  const { t } = useTranslation()

  const nodes = [
    { emoji: '\uD83C\uDF10', name: t('landing.archBrowser'), role: t('landing.archBrowserRole') },
    { emoji: '\uD83C\uDFDB\uFE0F', name: 'Gateway', role: t('landing.archGatewayRole') },
    { emoji: '\u2699\uFE0F', name: 'Worker', role: t('landing.archWorkerRole') },
  ]

  return (
    <section className="py-20">
      <div className="max-w-[960px] mx-auto px-6">
        <div className="text-center mb-14">
          <h2 className="text-[32px] font-bold tracking-tight mb-3">
            {t('landing.archTitle')}
          </h2>
          <p className="text-base text-[#a1a1aa] max-w-[500px] mx-auto">
            {t('landing.archDesc')}
          </p>
        </div>
        <div className="flex items-center gap-6 justify-center flex-wrap mb-12">
          {nodes.map((node, i) => (
            <div key={node.name} className="flex items-center gap-6">
              <div className="bg-[#121214] border border-[#2e2e36] rounded-xl px-7 py-6 text-center min-w-[180px] hover:border-emerald-500 transition-colors">
                <div className="text-[28px] mb-2.5">{node.emoji}</div>
                <div className="font-bold text-lg mb-1">{node.name}</div>
                <div className="text-[13px] text-[#71717a]">{node.role}</div>
              </div>
              {i < nodes.length - 1 && (
                <span className="text-xl text-emerald-500 font-mono shrink-0 px-1">
                  &rarr;
                </span>
              )}
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
