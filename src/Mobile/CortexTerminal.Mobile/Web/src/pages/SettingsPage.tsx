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
  IonGrid,
  IonRow,
  IonCol,
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
} from "ionicons/icons"
import type { ConsoleApi } from "../services/consoleApi"

type Theme = "light" | "dark" | "system"

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
  }

  const handleLanguageChange = (lang: string) => {
    setLanguage(lang)
    localStorage.setItem("cortex_mobile_lang", lang)
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

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonTitle>{t('settings.title')}</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
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

        <div className="ion-padding-horizontal ion-margin-top">
          <p className="section-label">{t('settings.appearance')}</p>
        </div>
        <IonGrid className="ion-padding-horizontal">
          <IonRow>
            {themes.map(({ value, label, icon }) => (
              <IonCol key={value}>
                <IonButton
                  fill={theme === value ? "solid" : "outline"}
                  size="small"
                  expand="block"
                  onClick={() => handleThemeChange(value)}
                >
                  <IonIcon icon={icon} slot="start" />
                  {label}
                </IonButton>
              </IonCol>
            ))}
          </IonRow>
        </IonGrid>

        <div className="ion-padding-horizontal ion-margin-top">
          <p className="section-label">{t('settings.language')}</p>
        </div>
        <IonGrid className="ion-padding-horizontal">
          <IonRow>
            {languages.map(({ value, label }) => (
              <IonCol key={value}>
                <IonButton
                  fill={language === value ? "solid" : "outline"}
                  size="small"
                  expand="block"
                  onClick={() => handleLanguageChange(value)}
                >
                  <IonIcon icon={globeOutline} slot="start" />
                  {label}
                </IonButton>
              </IonCol>
            ))}
          </IonRow>
        </IonGrid>

        <div className="ion-padding-horizontal ion-margin-top">
          <p className="section-label">{t('settings.account')}</p>
        </div>
        <IonList className="ion-padding-horizontal">
          <IonItem button detail onClick={openActivateModal}>
            <IonIcon icon={keyOutline} slot="start" color="primary" />
            <IonLabel>{t('settings.activateWorker')}</IonLabel>
          </IonItem>
          <IonItem
            button
            detail={false}
            onClick={onLogout}
            style={{ color: "var(--ion-color-danger)" }}
          >
            <IonIcon
              icon={logOutOutline}
              slot="start"
              color="danger"
            />
            <IonLabel color="danger">{t('settings.signOut')}</IonLabel>
          </IonItem>
        </IonList>

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
