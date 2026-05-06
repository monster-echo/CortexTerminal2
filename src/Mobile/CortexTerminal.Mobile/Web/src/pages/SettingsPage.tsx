import { useState, useEffect } from "react"
import { useTranslation } from "react-i18next"
import {
  IonPage,
  IonHeader,
  IonToolbar,
  IonTitle,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonIcon,
  IonButton,
  IonCard,
  IonCardContent,
  IonText,
  IonModal,
  IonInput,
} from "@ionic/react"
import {
  personOutline,
  moonOutline,
  sunnyOutline,
  desktopOutline,
  globeOutline,
  logOutOutline,
  keyOutline,
  closeOutline,
  checkmarkCircleOutline,
  checkmarkOutline,
} from "ionicons/icons"
import type { ConsoleApi } from "../services/consoleApi"

type Theme = "light" | "dark" | "system"

const themeIconMap: Record<Theme, string> = {
  light: sunnyOutline,
  dark: moonOutline,
  system: desktopOutline,
}

function getStoredTheme(): Theme {
  return (localStorage.getItem("theme") as Theme) ?? "system"
}

function applyTheme(theme: Theme) {
  const root = document.documentElement
  if (theme === "system") {
    const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches
    root.classList.toggle("dark", prefersDark)
  } else {
    root.classList.toggle("dark", theme === "dark")
  }
}

export function SettingsPage({
  username,
  onLogout,
  api,
}: {
  username: string | null
  onLogout: () => void
  api: ConsoleApi
}) {
  const { t } = useTranslation()
  const [theme, setTheme] = useState<Theme>(getStoredTheme)
  const [gatewayVersion, setGatewayVersion] = useState<string>("")
  const [language, setLanguage] = useState<string>(
    () => localStorage.getItem("cortex_mobile_lang") ?? navigator.language.startsWith("zh") ? "zh" : "en"
  )

  // sheet modals
  const [showThemeSheet, setShowThemeSheet] = useState(false)
  const [showLangSheet, setShowLangSheet] = useState(false)

  // activate modal state
  const [showActivate, setShowActivate] = useState(false)
  const [activateCode, setActivateCode] = useState("")
  const [activateLoading, setActivateLoading] = useState(false)
  const [activateSuccess, setActivateSuccess] = useState(false)
  const [activateError, setActivateError] = useState("")

  useEffect(() => {
    applyTheme(theme)
  }, [theme])

  useEffect(() => {
    api
      .getGatewayInfo()
      .then((info) => setGatewayVersion(info.version))
      .catch(() => {})
  }, [api])

  const handleThemeChange = (value: Theme) => {
    setTheme(value)
    localStorage.setItem("theme", value)
    applyTheme(value)
    setShowThemeSheet(false)
  }

  const handleLanguageChange = (lang: string) => {
    setLanguage(lang)
    localStorage.setItem("cortex_mobile_lang", lang)
    setShowLangSheet(false)
    window.location.reload()
  }

  const openActivateModal = () => {
    setActivateCode("")
    setActivateLoading(false)
    setActivateSuccess(false)
    setActivateError("")
    setShowActivate(true)
  }

  const handleActivate = async () => {
    const code = activateCode.trim().toUpperCase()
    if (!code) return
    setActivateLoading(true)
    setActivateError("")
    try {
      await api.verifyDeviceCode(code)
      setActivateSuccess(true)
    } catch {
      setActivateError(t('settings.activateError'))
    } finally {
      setActivateLoading(false)
    }
  }

  const themes: { value: Theme; label: string; icon: string }[] = [
    { value: "light", label: t('settings.themeLight'), icon: sunnyOutline },
    { value: "dark", label: t('settings.themeDark'), icon: moonOutline },
    { value: "system", label: t('settings.themeSystem'), icon: desktopOutline },
  ]

  const languages: { value: string; label: string }[] = [
    { value: "en", label: "English" },
    { value: "zh", label: "中文" },
  ]

  const currentThemeLabel = themes.find(t => t.value === theme)?.label ?? ""
  const currentLangLabel = languages.find(l => l.value === language)?.label ?? ""

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonTitle>{t('settings.title')}</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        {/* User card */}
        <IonCard className="ion-margin">
          <IonCardContent>
            <IonItem lines="none">
              <IonIcon icon={personOutline} slot="start" color="primary" />
              <IonLabel>
                <h3>{username ?? "User"}</h3>
                <p>{t('settings.gatewayConsole')}</p>
              </IonLabel>
            </IonItem>
          </IonCardContent>
        </IonCard>

        {/* General settings */}
        <IonList className="ion-margin-top" lines="inset">
          <IonItem button detail onClick={() => setShowThemeSheet(true)}>
            <IonIcon icon={themeIconMap[theme]} slot="start" color="primary" />
            <IonLabel>{t('settings.appearance')}</IonLabel>
            <IonLabel slot="end" color="medium" style={{ fontSize: 14 }}>{currentThemeLabel}</IonLabel>
          </IonItem>
          <IonItem button detail onClick={() => setShowLangSheet(true)}>
            <IonIcon icon={globeOutline} slot="start" color="primary" />
            <IonLabel>{t('settings.language')}</IonLabel>
            <IonLabel slot="end" color="medium" style={{ fontSize: 14 }}>{currentLangLabel}</IonLabel>
          </IonItem>
        </IonList>

        {/* Account */}
        <IonList className="ion-margin-top" lines="inset">
          <IonItem button detail onClick={openActivateModal}>
            <IonIcon icon={keyOutline} slot="start" color="primary" />
            <IonLabel>{t('settings.activateWorker')}</IonLabel>
          </IonItem>
          <IonItem button onClick={onLogout}>
            <IonIcon icon={logOutOutline} slot="start" color="danger" />
            <IonLabel color="danger">{t('settings.signOut')}</IonLabel>
          </IonItem>
        </IonList>

        {/* Theme Sheet Modal */}
        <IonModal
          isOpen={showThemeSheet}
          onDidDismiss={() => setShowThemeSheet(false)}
          breakpoints={[0, 0.5, 1]}
          initialBreakpoint={0.5}
          handle
        >
          <IonContent>
            <IonList lines="full">
              {themes.map(({ value, label, icon }) => (
                <IonItem
                  key={value}
                  button
                  onClick={() => handleThemeChange(value)}
                  detail={false}
                >
                  <IonIcon icon={icon} slot="start" color={theme === value ? "primary" : "medium"} />
                  <IonLabel>{label}</IonLabel>
                  {theme === value && (
                    <IonIcon icon={checkmarkOutline} slot="end" color="primary" />
                  )}
                </IonItem>
              ))}
            </IonList>
          </IonContent>
        </IonModal>

        {/* Language Sheet Modal */}
        <IonModal
          isOpen={showLangSheet}
          onDidDismiss={() => setShowLangSheet(false)}
          breakpoints={[0, 0.5, 1]}
          initialBreakpoint={0.5}
          handle
        >
          <IonContent>
            <IonList lines="full">
              {languages.map(({ value, label }) => (
                <IonItem
                  key={value}
                  button
                  onClick={() => handleLanguageChange(value)}
                  detail={false}
                >
                  <IonLabel>{label}</IonLabel>
                  {language === value && (
                    <IonIcon icon={checkmarkOutline} slot="end" color="primary" />
                  )}
                </IonItem>
              ))}
            </IonList>
          </IonContent>
        </IonModal>

        {/* Activate Worker Modal */}
        <IonModal isOpen={showActivate} onDidDismiss={() => setShowActivate(false)}>
          <IonHeader>
            <IonToolbar>
              <IonTitle>{t('settings.activateWorker')}</IonTitle>
              <IonButton slot="end" fill="clear" onClick={() => setShowActivate(false)}>
                <IonIcon icon={closeOutline} />
              </IonButton>
            </IonToolbar>
          </IonHeader>
          <IonContent className="ion-padding">
            {activateSuccess ? (
              <div style={{ textAlign: "center", marginTop: 60 }}>
                <IonIcon
                  icon={checkmarkCircleOutline}
                  style={{ fontSize: 64, color: "var(--ion-color-success)" }}
                />
                <h2>{t('settings.activateSuccess')}</h2>
                <IonButton
                  expand="block"
                  style={{ marginTop: 24 }}
                  onClick={() => setShowActivate(false)}
                >
                  OK
                </IonButton>
              </div>
            ) : (
              <div style={{ marginTop: 32 }}>
                <p style={{ textAlign: "center", color: "var(--ion-color-medium)", marginBottom: 24 }}>
                  {t('settings.activateDesc')}
                </p>
                <IonInput
                  value={activateCode}
                  onIonInput={(e) => {
                    const v = (e.detail.value ?? "").toUpperCase()
                    setActivateCode(v)
                    setActivateError("")
                  }}
                  placeholder={t('settings.activatePlaceholder')}
                  maxlength={9}
                  autocomplete="off"
                  style={{
                    fontSize: 24,
                    textAlign: "center",
                    fontFamily: "monospace",
                    letterSpacing: 4,
                    "--padding-start": "0",
                    "--padding-end": "0",
                  }}
                  onKeyDown={(e) => {
                    if (e.key === "Enter") handleActivate()
                  }}
                />
                {activateError && (
                  <p style={{ color: "var(--ion-color-danger)", textAlign: "center", marginTop: 12, fontSize: 14 }}>
                    {activateError}
                  </p>
                )}
                <IonButton
                  expand="block"
                  style={{ marginTop: 24 }}
                  onClick={handleActivate}
                  disabled={activateLoading || !activateCode.trim()}
                >
                  {activateLoading ? t('common.loading') : t('settings.activateButton')}
                </IonButton>
              </div>
            )}
          </IonContent>
        </IonModal>

        <div className="ion-text-center ion-margin-top ion-padding-horizontal">
          <IonText color="medium">
            <p style={{ fontSize: 12 }}>
              {t('settings.gatewayVersion', { version: gatewayVersion })}
            </p>
          </IonText>
        </div>
      </IonContent>
    </IonPage>
  )
}
