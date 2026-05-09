import { useTranslation } from 'react-i18next'

const features = [
  { icon: '\uD83D\uDCBB', titleKey: 'landing.feat1Title', descKey: 'landing.feat1Desc' },
  { icon: '\uD83D\uDD12', titleKey: 'landing.feat2Title', descKey: 'landing.feat2Desc' },
  { icon: '\uD83D\uDCE1', titleKey: 'landing.feat3Title', descKey: 'landing.feat3Desc' },
  { icon: '\uD83C\uDFD7\uFE0F', titleKey: 'landing.feat4Title', descKey: 'landing.feat4Desc' },
  { icon: '\uD83D\uDD04', titleKey: 'landing.feat5Title', descKey: 'landing.feat5Desc' },
  { icon: '\uD83D\uDCE6', titleKey: 'landing.feat6Title', descKey: 'landing.feat6Desc' },
] as const

export function FeaturesSection() {
  const { t } = useTranslation()

  return (
    <section className="py-0">
      <div className="max-w-[960px] mx-auto px-6">
        <div className="text-center mb-14">
          <h2 className="text-[32px] font-bold tracking-tight mb-3">
            {t('landing.featuresTitle')}
          </h2>
          <p className="text-base text-[#a1a1aa] max-w-[500px] mx-auto">
            {t('landing.featuresDesc')}
          </p>
        </div>
        <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
          {features.map((feat) => (
            <div
              key={feat.titleKey}
              className="bg-[#121214] border border-[#2e2e36] rounded-xl p-6 hover:border-emerald-500 transition-colors"
            >
              <div className="w-10 h-10 bg-[#242429] rounded-md flex items-center justify-center text-xl mb-3.5">
                {feat.icon}
              </div>
              <h3 className="text-base font-semibold mb-1.5">{t(feat.titleKey)}</h3>
              <p className="text-sm text-[#a1a1aa] leading-relaxed">
                {t(feat.descKey)}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
