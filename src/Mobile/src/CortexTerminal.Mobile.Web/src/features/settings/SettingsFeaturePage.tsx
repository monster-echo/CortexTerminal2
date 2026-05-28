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
  useIonToast,
} from "@ionic/react";
import {
  clipboardOutline,
  contrastOutline,
  documentTextOutline,
  keyOutline,
  languageOutline,
  logOutOutline,
  shieldCheckmarkOutline,
  trashOutline,
} from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { useAppStore, type AppStoreState } from "../../store/appStore";
import { useAuthStore, type AuthState } from "../../store/authStore";
import { authBridge } from "../../bridge/modules/authBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
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
  const [presentToast] = useIonToast();

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

  const handleDeleteAccount = () => {
    presentAlert({
      header: t("settings.deleteAccountConfirmTitle"),
      message: t("settings.deleteAccountConfirmMessage"),
      buttons: [
        { text: t("settings.cancel"), role: "cancel" },
        {
          text: t("settings.deleteAccountConfirm"),
          role: "destructive",
          handler: () => {
            presentAlert({
              header: t("settings.deleteAccountConfirmTitle"),
              message: t("settings.deleteAccountFinalConfirm"),
              buttons: [
                { text: t("settings.cancel"), role: "cancel" },
                {
                  text: t("settings.deleteAccountConfirm"),
                  role: "destructive",
                  handler: () => void deleteAccount(),
                },
              ],
            });
          },
        },
      ],
    });
  };

  const deleteAccount = async () => {
    try {
      await authBridge.deleteAccount();
      clearSession();
      void presentToast({
        message: t("settings.deleteAccountSuccess"),
        duration: 2000,
        position: "bottom",
        color: "success",
      });
      history.replace("/sessions");
    } catch (e) {
      console.error("[settings] Delete account failed:", e);
      void presentToast({
        message: e instanceof Error ? e.message : String(e),
        duration: 3000,
        position: "bottom",
        color: "danger",
      });
    }
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

  const openLink = (url: string) => {
    void nativeBridge.openExternalLink(url);
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
        </IonList>

        <div style={{ marginTop: 24 }}>
          <IonList inset>
            <IonItem button onClick={handleLogout} detail={false}>
              <IonIcon slot="start" icon={logOutOutline} color="danger" />
              <IonLabel color="danger">{t("sidebar.logout")}</IonLabel>
            </IonItem>
            <IonItem button onClick={handleDeleteAccount} detail={false}>
              <IonIcon slot="start" icon={trashOutline} color="danger" />
              <IonLabel color="danger">{t("settings.deleteAccount")}</IonLabel>
            </IonItem>
          </IonList>
        </div>

        <div style={{
          textAlign: "center",
          padding: "16px 0 4px",
        }}>
          <IonItem button={false} lines="none" style={{ "--background": "transparent", "--padding-start": "0" }}>
            <div style={{ display: "flex", justifyContent: "center", gap: 24, width: "100%" }}>
              <a
                onClick={(e) => { e.preventDefault(); openLink(appInfo?.privacyPolicyUrl ?? ""); }}
                style={{ color: "var(--ion-color-medium)", fontSize: 12, cursor: "pointer", textDecoration: "underline" }}
              >
                <IonIcon icon={shieldCheckmarkOutline} style={{ fontSize: 14, marginRight: 4, verticalAlign: "middle" }} />
                {t("settings.privacy")}
              </a>
              <a
                onClick={(e) => { e.preventDefault(); openLink(appInfo?.termsOfServiceUrl ?? ""); }}
                style={{ color: "var(--ion-color-medium)", fontSize: 12, cursor: "pointer", textDecoration: "underline" }}
              >
                <IonIcon icon={documentTextOutline} style={{ fontSize: 14, marginRight: 4, verticalAlign: "middle" }} />
                {t("settings.terms")}
              </a>
            </div>
          </IonItem>
        </div>

        <div style={{
          textAlign: "center",
          color: "var(--ion-color-medium)",
          fontSize: 12,
          padding: "4px 0 24px",
        }}>
          v{appInfo?.appVersion ?? "..."}
        </div>
      </IonContent>
    </IonPage>
  );
}
