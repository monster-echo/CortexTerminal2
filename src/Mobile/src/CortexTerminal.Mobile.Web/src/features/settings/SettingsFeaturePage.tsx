import { useState, useCallback } from "react";
import {
  IonContent,
  IonIcon,
  IonItem,
  IonItemDivider,
  IonLabel,
  IonList,
  IonPage,
  IonModal,
  IonButton,
  useIonActionSheet,
  useIonAlert,
  useIonToast,
} from "@ionic/react";
import {
  cameraOutline,
  contrastOutline,
  documentTextOutline,
  keyOutline,
  languageOutline,
  lockClosedOutline,
  logOutOutline,
  shieldCheckmarkOutline,
} from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useTranslation } from "react-i18next";
import Cropper from "react-easy-crop";
import type { Area } from "react-easy-crop";
import PageHeader from "../../components/PageHeader";
import { useAppStore, type AppStoreState } from "../../store/appStore";
import { useAuthStore, type AuthState } from "../../store/authStore";
import { authBridge } from "../../bridge/modules/authBridge";
import { deviceBridge } from "../../bridge/modules/deviceBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import UserAvatar from "../../components/UserAvatar";
import {
  applyColorMode,
  setStoredMode,
  type ColorMode,
} from "../../theme/colorMode";
import cropImage from "../../utils/cropImage";

const selectAppInfo = (s: AppStoreState) => s.appInfo;
const selectColorMode = (s: AppStoreState) => s.colorMode;
const selectSetColorMode = (s: AppStoreState) => s.setColorMode;
const selectLanguage = (s: AppStoreState) => s.language;
const selectSetLanguage = (s: AppStoreState) => s.setLanguage;
const selectUser = (s: AuthState) => s.user;
const selectClearSession = (s: AuthState) => s.clearSession;
const selectSetSession = (s: AuthState) => s.setSession;

export default function SettingsFeaturePage({ history }: RouteComponentProps) {
  const { t } = useTranslation();
  const appInfo = useAppStore(selectAppInfo);
  const user = useAuthStore(selectUser);
  const clearSession = useAuthStore(selectClearSession);
  const setSession = useAuthStore(selectSetSession);
  const colorMode = useAppStore(selectColorMode);
  const setColorModeState = useAppStore(selectSetColorMode);
  const language = useAppStore(selectLanguage);
  const setLanguage = useAppStore(selectSetLanguage);
  const [presentActionSheet] = useIonActionSheet();
  const [presentAlert] = useIonAlert();
  const [presentToast] = useIonToast();

  const [showCropModal, setShowCropModal] = useState(false);
  const [cropSrc, setCropSrc] = useState<string | null>(null);
  const [crop, setCrop] = useState({ x: 0, y: 0 });
  const [zoom, setZoom] = useState(1);
  const [croppedAreaPixels, setCroppedAreaPixels] = useState<Area | null>(null);
  const [avatarSubmitting, setAvatarSubmitting] = useState(false);

  const onCropComplete = useCallback((_croppedArea: Area, croppedAreaPx: Area) => {
    setCroppedAreaPixels(croppedAreaPx);
  }, []);

  const handleAvatarClick = () => {
    presentActionSheet({
      header: t("settings.changeAvatar"),
      buttons: [
        {
          text: t("settings.selectFromAlbum"),
          handler: () => void pickAndCrop(),
        },
        { text: t("settings.cancel"), role: "cancel" },
      ],
    });
  };

  const pickAndCrop = async () => {
    try {
      const asset = await deviceBridge.pickPhoto();
      if (!asset?.localUrl) return;
      const response = await fetch(asset.localUrl);
      const blob = await response.blob();
      const base64 = await new Promise<string>((resolve) => {
        const reader = new FileReader();
        reader.onloadend = () => resolve(reader.result as string);
        reader.readAsDataURL(blob);
      });
      setCropSrc(base64);
      setCrop({ x: 0, y: 0 });
      setZoom(1);
      setShowCropModal(true);
    } catch (e) {
      void presentToast({ message: e instanceof Error ? e.message : String(e), duration: 3000, position: "bottom", color: "warning" });
    }
  };

  const handleCropConfirm = async () => {
    if (!cropSrc || !croppedAreaPixels) return;
    setAvatarSubmitting(true);
    try {
      const base64 = await cropImage(cropSrc, croppedAreaPixels);
      const result = await authBridge.updateAvatar(base64);
      if (result.success && result.avatarUrl) {
        if (user) setSession({ ...user, avatarUrl: result.avatarUrl }, "");
        void presentToast({ message: t("settings.avatarUpdated"), duration: 2000, position: "bottom", color: "success" });
      }
      setShowCropModal(false);
      setCropSrc(null);
    } catch (e) {
      void presentToast({ message: e instanceof Error ? e.message : String(e), duration: 3000, position: "bottom", color: "warning" });
    } finally {
      setAvatarSubmitting(false);
    }
  };

  const handleCropCancel = () => {
    setShowCropModal(false);
    setCropSrc(null);
  };

  const logout = async () => {
    try {
      await authBridge.logout();
    } catch (e) {
      console.warn(
        "[settings] Bridge logout failed, clearing local session:",
        e,
      );
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

  const openLink = (url: string) => {
    void nativeBridge.openExternalLink(url);
  };

  return (
    <IonPage>
      <PageHeader title={t("settings.title")} defaultHref="/sessions" />
      <IonContent fullscreen>
        <div style={{ display: "flex", flexDirection: "column", alignItems: "center", padding: "24px 0 8px" }}>
          <div
            onClick={avatarSubmitting ? undefined : handleAvatarClick}
            style={{ position: "relative", cursor: "pointer" }}
          >
            <UserAvatar username={user?.username} avatarUrl={user?.avatarUrl} style={{ width: 80, height: 80, fontSize: 32 }} />
            {avatarSubmitting && (
              <IonIcon
                icon={cameraOutline}
                className="ion-spin"
                style={{
                  position: "absolute",
                  bottom: 0,
                  right: 0,
                  background: "var(--ion-color-primary)",
                  color: "#fff",
                  borderRadius: "50%",
                  padding: 4,
                  fontSize: 16,
                }}
              />
            )}
          </div>
          <IonLabel style={{ marginTop: 8, fontSize: 18, fontWeight: 600 }}>
            {user?.username ?? "..."}
          </IonLabel>
        </div>

        <IonList inset>
          <IonItemDivider>
            <IonLabel className="py-2">
              {t("settings.appearanceSection")}
            </IonLabel>
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
            <IonLabel className="py-2">{t("settings.featureSection")}</IonLabel>
          </IonItemDivider>
          <IonItem button routerLink="/activate" routerDirection="root">
            <IonIcon slot="start" icon={keyOutline} />
            <IonLabel>{t("settings.activateWorker")}</IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonItemDivider>
            <IonLabel className="py-2">{t("settings.securitySection")}</IonLabel>
          </IonItemDivider>
          <IonItem button routerLink="/settings/security" routerDirection="forward">
            <IonIcon slot="start" icon={lockClosedOutline} />
            <IonLabel>{t("settings.securitySection")}</IonLabel>
          </IonItem>
        </IonList>

        <div style={{ marginTop: 24 }}>
          <IonList inset>
            <IonItem button onClick={handleLogout} detail={false}>
              <IonIcon slot="start" icon={logOutOutline} color="danger" />
              <IonLabel color="danger">{t("sidebar.logout")}</IonLabel>
            </IonItem>
          </IonList>
        </div>

        <div
          style={{
            textAlign: "center",
            padding: "16px 0 4px",
          }}
        >
          <IonItem
            button={false}
            lines="none"
            style={{ "--background": "transparent", "--padding-start": "0" }}
          >
            <div
              style={{
                display: "flex",
                justifyContent: "center",
                gap: 24,
                width: "100%",
              }}
            >
              <a
                onClick={(e) => {
                  e.preventDefault();
                  openLink(appInfo?.privacyPolicyUrl ?? "");
                }}
                style={{
                  color: "var(--ion-color-medium)",
                  fontSize: 12,
                  cursor: "pointer",
                  textDecoration: "underline",
                }}
              >
                <IonIcon
                  icon={shieldCheckmarkOutline}
                  style={{
                    fontSize: 14,
                    marginRight: 4,
                    verticalAlign: "middle",
                  }}
                />
                {t("settings.privacy")}
              </a>
              <a
                onClick={(e) => {
                  e.preventDefault();
                  openLink(appInfo?.termsOfServiceUrl ?? "");
                }}
                style={{
                  color: "var(--ion-color-medium)",
                  fontSize: 12,
                  cursor: "pointer",
                  textDecoration: "underline",
                }}
              >
                <IonIcon
                  icon={documentTextOutline}
                  style={{
                    fontSize: 14,
                    marginRight: 4,
                    verticalAlign: "middle",
                  }}
                />
                {t("settings.terms")}
              </a>
            </div>
          </IonItem>
        </div>

        <div
          style={{
            textAlign: "center",
            color: "var(--ion-color-medium)",
            fontSize: 12,
            padding: "4px 0 24px",
          }}
        >
          v{appInfo?.appVersion ?? "..."}
        </div>
      </IonContent>

      {/* Avatar Crop Modal */}
      <IonModal isOpen={showCropModal} onDidDismiss={handleCropCancel}>
        <IonContent fullscreen style={{ "--background": "#000" }}>
          {cropSrc && (
            <div style={{ position: "relative", width: "100%", height: "100%" }}>
              <Cropper
                image={cropSrc}
                crop={crop}
                zoom={zoom}
                aspect={1}
                cropShape="round"
                onCropChange={setCrop}
                onZoomChange={setZoom}
                onCropComplete={onCropComplete}
              />
            </div>
          )}
          <div style={{ position: "absolute", bottom: 0, left: 0, right: 0, padding: 16, background: "rgba(0,0,0,0.6)" }}>
            <IonButton expand="block" onClick={handleCropConfirm} disabled={avatarSubmitting}>
              {avatarSubmitting ? t("settings.cancel") : t("settings.cropConfirm")}
            </IonButton>
            <IonButton expand="block" fill="outline" color="light" onClick={handleCropCancel} disabled={avatarSubmitting}>
              {t("settings.cancel")}
            </IonButton>
          </div>
        </IonContent>
      </IonModal>
    </IonPage>
  );
}
