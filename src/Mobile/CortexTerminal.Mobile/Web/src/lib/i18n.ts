import i18n from 'i18next'
import { initReactI18next } from 'react-i18next'
import en from '../locales/en.json'
import zh from '../locales/zh.json'

const savedLang = localStorage.getItem('cortex_mobile_lang')
const detectedLang = savedLang ?? (navigator.language.startsWith('zh') ? 'zh' : 'en')

i18n
  .use(initReactI18next)
  .init({
    resources: { en: { translation: en }, zh: { translation: zh } },
    lng: detectedLang,
    fallbackLng: 'en',
    supportedLngs: ['en', 'zh'],
    interpolation: { escapeValue: false },
  })

export default i18n
