import { useTranslation } from 'react-i18next'
import { Download } from 'lucide-react'
import { InstallCommand } from './install-command'

export function HeroSection() {
  const { t } = useTranslation()

  return (
    <section className='pt-24 pb-16 text-center'>
      <div className='mb-7 inline-flex items-center gap-1.5 rounded-full border border-emerald-500/20 bg-emerald-500/15 px-3 py-1 text-[13px] font-medium text-emerald-500'>
        <span className='h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-500' />
        {t('landing.heroBadge')}
      </div>
      <h1 className='mb-4 text-[clamp(36px,5.5vw,56px)] leading-[1.1] font-extrabold tracking-tight'>
        {t('landing.heroTitle')}
        <br />
        <span className='text-emerald-500'>{t('landing.heroTitleAccent')}</span>
      </h1>
      <p className='mx-auto mb-10 max-w-[560px] text-lg leading-relaxed text-[#a1a1aa]'>
        {t('landing.heroDesc')}
      </p>

      <InstallCommand className='mb-4' />

      <p className='mb-2 text-[13px] text-[#71717a]'>
        {t('landing.installHint')}
      </p>
      <div className='mb-12 flex flex-wrap justify-center gap-2'>
        {[
          'linux/amd64',
          'linux/arm64',
          'macOS (Apple Silicon)',
          'Windows x64',
          'Docker',
        ].map((tag) => (
          <span
            key={tag}
            className='rounded-full border border-[#2e2e36] px-2.5 py-[3px] font-mono text-xs text-[#71717a]'
          >
            {tag}
          </span>
        ))}
      </div>

      <div className='mt-10 flex flex-wrap items-start justify-center gap-6 border-t border-[#2e2e36] pt-10'>
        <div className='flex flex-col items-center'>
          <div className='mb-3 h-[120px] w-[120px] rounded-xl bg-white p-2'>
            <img
              src='/corterm_googleplay_qr.png'
              alt='Google Play'
              className='h-full w-full object-contain'
            />
          </div>
          <span className='text-sm text-[#a1a1aa]'>Android / Google Play</span>
        </div>
        <div className='flex flex-col items-center'>
          <div className='mb-3 h-[120px] w-[120px] rounded-xl bg-white p-2'>
            <img
              src='/corterm_appstore_qr.png'
              alt='App Store'
              className='h-full w-full object-contain'
            />
          </div>
          <span className='text-sm text-[#a1a1aa]'>iOS / App Store</span>
        </div>
        <div className='flex flex-col items-center'>
          <div className='mb-3 h-[120px] w-[120px] rounded-xl bg-white p-2'>
            <img
              src='/corterm_appgallery_qr.png'
              alt='AppGallery'
              className='h-full w-full object-contain'
            />
          </div>
          <span className='text-sm text-[#a1a1aa]'>{t('landing.mobileAppGallery')}</span>
        </div>
        <a
          href='https://minio.myhome.rwecho.top:8443/minio/n8n-data/corterm/android/'
          target='_blank'
          rel='noopener'
          className='flex flex-col items-center group no-underline'
        >
          <div className='mb-3 h-[120px] w-[120px] rounded-xl bg-white flex items-center justify-center group-hover:bg-emerald-50 transition-colors'>
            <Download className='h-10 w-10 text-[#71717a] group-hover:text-emerald-600 transition-colors' />
          </div>
          <span className='text-sm text-[#a1a1aa] group-hover:text-[#e4e4e7] transition-colors'>
            {t('landing.mobileApkDirect')}
          </span>
        </a>
      </div>
    </section>
  )
}
