import { useTranslation } from 'react-i18next'

export function QuickStartSection() {
  const { t } = useTranslation()

  const steps = [
    { num: 1, titleKey: 'landing.step1Title', descKey: 'landing.step1Desc' },
    { num: 2, titleKey: 'landing.step2Title', descKey: 'landing.step2Desc' },
    { num: 3, titleKey: 'landing.step3Title', descKey: 'landing.step3Desc' },
  ]

  return (
    <section
      id="quick-start"
      className="py-20 bg-[#121214] border-t border-b border-[#2e2e36]"
    >
      <div className="max-w-[960px] mx-auto px-6">
        <div className="text-center mb-14">
          <h2 className="text-[32px] font-bold tracking-tight mb-3">
            {t('landing.stepsTitle')}
          </h2>
          <p className="text-base text-[#a1a1aa] max-w-[500px] mx-auto">
            {t('landing.stepsDesc')}
          </p>
        </div>
        <div className="max-w-[640px] mx-auto flex flex-col gap-3">
          {steps.map((step) => (
            <div
              key={step.num}
              className="flex gap-3.5 bg-[#121214] border border-[#2e2e36] rounded-xl p-[18px] items-start"
            >
              <div className="w-8 h-8 bg-emerald-500/15 text-emerald-500 rounded-md flex items-center justify-center font-bold text-sm shrink-0 font-mono">
                {step.num}
              </div>
              <div>
                <h4 className="text-sm font-semibold mb-1">{t(step.titleKey)}</h4>
                <p className="text-[13px] text-[#a1a1aa]">{t(step.descKey)}</p>
              </div>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
