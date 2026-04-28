import { useTranslation } from 'react-i18next'
import { ContentSection } from '../components/content-section'
import { GeneralForm } from './general-form'

export function SettingsGeneral() {
  const { t } = useTranslation()
  return (
    <ContentSection
      title={t('settings.general')}
      desc='Configure language and theme preferences.'
    >
      <GeneralForm />
    </ContentSection>
  )
}
