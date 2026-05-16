import {
  IonContent,
  IonIcon,
  IonItem,
  IonItemDivider,
  IonLabel,
  IonList,
  IonPage,
  useIonActionSheet,
  useIonAlert,
} from "@ionic/react";
import {
  contrastOutline,
  keyOutline,
  languageOutline,
  logOutOutline,
} from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { useAppStore, type AppStoreState } from "../../store/appStore";
import { useAuthStore, type AuthState } from "../../store/authStore";
import { authBridge } from "../../bridge/modules/authBridge";
import {
  applyColorMode,
  setStoredMode,
  type ColorMode,
} from "../../theme/colorMode";

const selectAppInfo = (s: AppStoreState) => s.appInfo;
const selectColorMode = (s: AppStoreState) => s.colorMode;
const selectSetColorMode = (s: AppStoreState) => s.setColorMode;
const selectLanguage = (s: AppStoreState) => s.language;
const selectSetLanguage = (s: AppStoreState) => s.setLanguage;
const selectUser = (s: AuthState) => s.user;
const selectClearSession = (s: AuthState) => s.clearSession;

export default function SettingsFeaturePage({ history }: RouteComponentProps) {
  const { t } = useTranslation();
  const appInfo = useAppStore(selectAppInfo);
  const user = useAuthStore(selectUser);
  const clearSession = useAuthStore(selectClearSession);
  const colorMode = useAppStore(selectColorMode);
  const setColorModeState = useAppStore(selectSetColorMode);
  const language = useAppStore(selectLanguage);
  const setLanguage = useAppStore(selectSetLanguage);
  const [presentActionSheet] = useIonActionSheet();
  const [presentAlert] = useIonAlert();

  const logout = async () => {
    try {
      await authBridge.logout();
    } catch (e) {
      console.warn("[settings] Bridge logout failed, clearing local session:", e);
    }
    clearSession();
    history.replace("/sessions");
  };

  const handleLogout = () => {
    presentAlert({
      header: t("settings.logoutConfirmTitle"),
      message: t("settings.logoutConfirmMessage"),
      buttons: [
        { text: t("settings.cancel"), role: "cancel" },
        {
          text: t("settings.logoutConfirm"),
          role: "destructive",
          handler: () => void logout(),
        },
      ],
    });
  };

  const handleColorModeChange = (mode: ColorMode) => {
    setStoredMode(mode);
    applyColorMode(mode);
    setColorModeState(mode);
  };

  const handleThemeSelect = () => {
    presentActionSheet({
      header: t("settings.themeLabel"),
      buttons: [
        {
          text: t("settings.themeLight"),
          handler: () => handleColorModeChange("light"),
        },
        {
          text: t("settings.themeDark"),
          handler: () => handleColorModeChange("dark"),
        },
        {
          text: t("settings.themeSystem"),
          handler: () => handleColorModeChange("system"),
        },
        {
          text: t("settings.cancel"),
          role: "cancel",
        },
      ],
    });
  };

  const handleLanguageSelect = () => {
    presentActionSheet({
      header: t("settings.languageLabel"),
      buttons: [
        {
          text: t("settings.languageZh"),
          handler: () => setLanguage("zh"),
        },
        {
          text: t("settings.languageEn"),
          handler: () => setLanguage("en"),
        },
        {
          text: t("settings.cancel"),
          role: "cancel",
        },
      ],
    });
  };

  const currentThemeLabel = (): string => {
    switch (colorMode) {
      case "light":
        return t("settings.themeLight");
      case "dark":
        return t("settings.themeDark");
      case "system":
        return t("settings.themeSystem");
    }
  };

  const currentLanguageLabel = (): string => {
    return language === "zh"
      ? t("settings.languageZh")
      : t("settings.languageEn");
  };

  return (
    <IonPage>
      <PageHeader title={t("settings.title")} defaultHref="/sessions" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItemDivider>
            <IonLabel>{t("settings.userSection")}</IonLabel>
          </IonItemDivider>
          <IonItem>
            <div slot="start" style={{
              width: 40, height: 40, borderRadius: "50%",
              background: "var(--ion-color-primary)",
              color: "var(--ion-color-primary-contrast)", display: "flex", alignItems: "center",
              justifyContent: "center", fontWeight: 600, fontSize: 18,
            }}>
              {(user?.username ?? "?")[0].toUpperCase()}
            </div>
            <IonLabel>
              <h2>{user?.username ?? "..."}</h2>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItemDivider>
            <IonLabel>{t("settings.appearanceSection")}</IonLabel>
          </IonItemDivider>
          <IonItem button onClick={handleThemeSelect}>
            <IonIcon slot="start" icon={contrastOutline} />
            <IonLabel>
              <h2>{t("settings.themeLabel")}</h2>
            </IonLabel>
            <IonLabel slot="end" color="medium">
              {currentThemeLabel()}
            </IonLabel>
          </IonItem>
          <IonItem button onClick={handleLanguageSelect}>
            <IonIcon slot="start" icon={languageOutline} />
            <IonLabel>
              <h2>{t("settings.languageLabel")}</h2>
              <p>{t("settings.languageDesc")}</p>
            </IonLabel>
            <IonLabel slot="end" color="medium">
              {currentLanguageLabel()}
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItemDivider>
            <IonLabel>{t("settings.featureSection")}</IonLabel>
          </IonItemDivider>
          <IonItem button routerLink="/activate" routerDirection="root">
            <IonIcon slot="start" icon={keyOutline} />
            <IonLabel>{t("settings.activateWorker")}</IonLabel>
          </IonItem>
          <IonItem button color="danger" onClick={handleLogout}>
            <IonIcon slot="start" icon={logOutOutline} />
            <IonLabel>{t("sidebar.logout")}</IonLabel>
          </IonItem>
        </IonList>

        <div style={{
          textAlign: "center",
          color: "var(--ion-color-medium)",
          fontSize: 12,
          padding: "24px 0",
        }}>
          v{appInfo?.appVersion ?? "..."}
        </div>
      </IonContent>
    </IonPage>
  );
}
