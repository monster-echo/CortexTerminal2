import { useTranslation } from 'react-i18next'

const features = [
  {
    icon: '\uD83D\uDCBB',
    titleKey: 'landing.feat1Title',
    descKey: 'landing.feat1Desc',
  },
  {
    icon: '\uD83D\uDD12',
    titleKey: 'landing.feat2Title',
    descKey: 'landing.feat2Desc',
  },
  {
    icon: '\uD83D\uDCE1',
    titleKey: 'landing.feat3Title',
    descKey: 'landing.feat3Desc',
  },
  {
    icon: '\uD83C\uDFD7\uFE0F',
    titleKey: 'landing.feat4Title',
    descKey: 'landing.feat4Desc',
  },
  {
    icon: '\uD83D\uDD04',
    titleKey: 'landing.feat5Title',
    descKey: 'landing.feat5Desc',
  },
  {
    icon: '\uD83D\uDCE6',
    titleKey: 'landing.feat6Title',
    descKey: 'landing.feat6Desc',
  },
] as const

export function FeaturesSection() {
  const { t } = useTranslation()

  return (
    <section className='py-24'>
      <div className='mx-auto max-w-[960px] px-6'>
        <div className='mb-14 text-center'>
          <h2 className='mb-3 text-[32px] font-bold tracking-tight'>
            {t('landing.featuresTitle')}
          </h2>
          <p className='mx-auto max-w-[500px] text-base text-[#a1a1aa]'>
            {t('landing.featuresDesc')}
          </p>
        </div>
        <div className='grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3'>
          {features.map((feat) => (
            <div
              key={feat.titleKey}
              className='rounded-xl border border-[#2e2e36] bg-[#121214] p-6 transition-colors hover:border-emerald-500'
            >
              <div className='mb-3.5 flex h-10 w-10 items-center justify-center rounded-md bg-[#242429] text-xl'>
                {feat.icon}
              </div>
              <h3 className='mb-1.5 text-base font-semibold'>
                {t(feat.titleKey)}
              </h3>
              <p className='text-sm leading-relaxed text-[#a1a1aa]'>
                {t(feat.descKey)}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
