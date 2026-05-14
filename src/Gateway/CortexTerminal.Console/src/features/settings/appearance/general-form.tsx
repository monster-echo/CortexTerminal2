import { useTranslation } from 'react-i18next'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { Separator } from '@/components/ui/separator'

export function GeneralForm() {
  const { t, i18n } = useTranslation()

  return (
    <div className='space-y-8'>
      <div className='space-y-2'>
        <Label>{t('settings.language')}</Label>
        <Select
          value={i18n.language.startsWith('zh') ? 'zh' : 'en'}
          onValueChange={(lang) => i18n.changeLanguage(lang)}
        >
          <SelectTrigger className='w-[200px]'>
            <SelectValue />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value='en'>English</SelectItem>
            <SelectItem value='zh'>中文</SelectItem>
          </SelectContent>
        </Select>
      </div>
      <Separator />
      <div className='space-y-2'>
        <Label>{t('settings.theme')}</Label>
        <p className='text-sm text-muted-foreground'>
          {t('settings.appearanceSection.hint')}
        </p>
      </div>
    </div>
  )
}
