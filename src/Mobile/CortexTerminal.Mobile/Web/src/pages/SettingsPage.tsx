import { useState, useEffect } from "react"
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
} from "@ionic/react"
import {
  personOutline,
  moonOutline,
  sunnyOutline,
  desktopOutline,
  globeOutline,
  logOutOutline,
} from "ionicons/icons"
import type { ConsoleApi } from "../services/consoleApi"

type Theme = "light" | "dark" | "system"

function getStoredTheme(): Theme {
  return (localStorage.getItem("theme") as Theme) ?? "dark"
}

function applyTheme(theme: Theme) {
  const root = document.documentElement
  if (theme === "system") {
    const prefersDark = window.matchMedia(
      "(prefers-color-scheme: dark)",
    ).matches
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
  const [theme, setTheme] = useState<Theme>(getStoredTheme)
  const [gatewayVersion, setGatewayVersion] = useState<string>("")

  useEffect(() => {
    applyTheme(theme)
  }, [theme])

  useEffect(() => {
    api
      .getGatewayInfo()
      .then((info) => setGatewayVersion(info.version))
      .catch(() => {})
  }, [api])

  const themes: { value: Theme; label: string; icon: string }[] = [
    { value: "light", label: "Light", icon: sunnyOutline },
    { value: "dark", label: "Dark", icon: moonOutline },
    { value: "system", label: "System", icon: desktopOutline },
  ]

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonTitle>Settings</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        <IonCard style={{ margin: 16 }}>
          <IonCardContent>
            <div style={{ display: "flex", alignItems: "center", gap: 12 }}>
              <div
                style={{
                  display: "flex",
                  alignItems: "center",
                  justifyContent: "center",
                  width: 44,
                  height: 44,
                  borderRadius: "50%",
                  backgroundColor: "var(--ion-color-primary-tint)",
                }}
              >
                <IonIcon
                  icon={personOutline}
                  style={{ fontSize: 22, color: "var(--ion-color-primary)" }}
                />
              </div>
              <div>
                <p style={{ fontWeight: 600, margin: 0 }}>
                  {username ?? "User"}
                </p>
                <IonText color="medium">
                  <p style={{ fontSize: 12, margin: 0 }}>Gateway Console</p>
                </IonText>
              </div>
            </div>
          </IonCardContent>
        </IonCard>

        <div style={{ padding: "0 16px", marginTop: 8 }}>
          <p
            style={{
              fontSize: 11,
              fontWeight: 600,
              textTransform: "uppercase",
              letterSpacing: "0.05em",
              color: "var(--ion-color-medium)",
              marginBottom: 8,
            }}
          >
            Appearance
          </p>
        </div>
        <div style={{ display: "flex", gap: 8, padding: "0 16px" }}>
          {themes.map(({ value, label, icon }) => (
            <IonButton
              key={value}
              fill={theme === value ? "solid" : "outline"}
              size="small"
              expand="block"
              onClick={() => {
                setTheme(value)
                localStorage.setItem("theme", value)
                applyTheme(value)
              }}
              style={{ flex: 1 }}
            >
              <IonIcon icon={icon} slot="start" />
              {label}
            </IonButton>
          ))}
        </div>

        <div style={{ padding: "0 16px", marginTop: 16 }}>
          <p
            style={{
              fontSize: 11,
              fontWeight: 600,
              textTransform: "uppercase",
              letterSpacing: "0.05em",
              color: "var(--ion-color-medium)",
              marginBottom: 8,
            }}
          >
            Language
          </p>
        </div>
        <div style={{ display: "flex", gap: 8, padding: "0 16px" }}>
          <IonButton fill="solid" size="small" expand="block" style={{ flex: 1 }}>
            <IonIcon icon={globeOutline} slot="start" />
            English
          </IonButton>
          <IonButton fill="outline" size="small" expand="block" style={{ flex: 1 }}>
            <IonIcon icon={globeOutline} slot="start" />
            中文
          </IonButton>
        </div>

        <div style={{ padding: "0 16px", marginTop: 16 }}>
          <p
            style={{
              fontSize: 11,
              fontWeight: 600,
              textTransform: "uppercase",
              letterSpacing: "0.05em",
              color: "var(--ion-color-medium)",
              marginBottom: 8,
            }}
          >
            Account
          </p>
        </div>
        <IonList style={{ margin: "0 16px" }}>
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
            <IonLabel color="danger">Sign out</IonLabel>
          </IonItem>
        </IonList>

        <div style={{ textAlign: "center", marginTop: 32, padding: "0 16px" }}>
          <IonText color="medium">
            <p style={{ fontSize: 12 }}>
              CortexTerminal Gateway{gatewayVersion ? ` v${gatewayVersion}` : ""}
            </p>
          </IonText>
        </div>
      </IonContent>
    </IonPage>
  )
}
