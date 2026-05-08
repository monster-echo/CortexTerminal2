import { useRef } from "react";
import {
  IonMenu,
  IonHeader,
  IonToolbar,
  IonTitle,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonIcon,
  IonFooter,
  IonNote,
  IonItemDivider,
  useIonToast,
} from "@ionic/react";
import {
  homeOutline,
  settingsOutline,
  colorPaletteOutline,
  logOutOutline,
  codeSlashOutline,
  radioOutline,
  constructOutline,
  extensionPuzzleOutline,
} from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { useAppStore } from "../store/appStore";
import { useAuthStore } from "../store/authStore";
import { authBridge } from "../bridge/modules/authBridge";

const DEBUG_TAP_THRESHOLD = 7;
const DEBUG_TAP_TIMEOUT_MS = 3000;

export default function AppSidebar() {
  const { t } = useTranslation();
  const debugMode = useAppStore((s) => s.debugMode);
  const setDebugMode = useAppStore((s) => s.setDebugMode);
  const appInfo = useAppStore((s) => s.appInfo);
  const platformLabel = useAppStore((s) => s.platformLabel);
  const user = useAuthStore((s) => s.user);
  const clearSession = useAuthStore((s) => s.clearSession);
  const [presentToast] = useIonToast();

  const tapCountRef = useRef(0);
  const tapTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);
  const menuRef = useRef<HTMLIonMenuElement>(null);

  const handleVersionTap = () => {
    tapCountRef.current += 1;

    if (tapTimerRef.current) {
      clearTimeout(tapTimerRef.current);
    }

    tapTimerRef.current = setTimeout(() => {
      tapCountRef.current = 0;
    }, DEBUG_TAP_TIMEOUT_MS);

    if (tapCountRef.current >= DEBUG_TAP_THRESHOLD) {
      tapCountRef.current = 0;
      if (tapTimerRef.current) {
        clearTimeout(tapTimerRef.current);
        tapTimerRef.current = undefined;
      }
      const nextMode = !debugMode;
      setDebugMode(nextMode);
      presentToast({
        message: nextMode ? t("sidebar.debugEnabled") : t("sidebar.debugDisabled"),
        duration: 1500,
        position: "bottom",
      });
    }
  };

  const handleLogout = async () => {
    try {
      await authBridge.logout();
    } catch {
      // ignore bridge errors on logout
    }
    clearSession();
  };

  const closeMenu = () => {
    menuRef.current?.close();
  };

  return (
    <IonMenu ref={menuRef} side="start" menuId="main-menu" contentId="main-content">
      <IonHeader>
        <IonToolbar>
          <IonTitle>{t("sidebar.title")}</IonTitle>
        </IonToolbar>
      </IonHeader>

      <IonContent>
        <IonList>
          <IonItem button routerLink="/home" routerDirection="root" onClick={closeMenu}>
            <IonIcon slot="start" icon={homeOutline} />
            <IonLabel>{t("sidebar.home")}</IonLabel>
          </IonItem>
          <IonItem button routerLink="/settings" routerDirection="root" onClick={closeMenu}>
            <IonIcon slot="start" icon={settingsOutline} />
            <IonLabel>{t("sidebar.settings")}</IonLabel>
          </IonItem>
          <IonItem button routerLink="/theme" routerDirection="root" onClick={closeMenu}>
            <IonIcon slot="start" icon={colorPaletteOutline} />
            <IonLabel>{t("sidebar.theme")}</IonLabel>
          </IonItem>
          <IonItem button routerLink="/components" routerDirection="root" onClick={closeMenu}>
            <IonIcon slot="start" icon={extensionPuzzleOutline} />
            <IonLabel>{t("sidebar.components")}</IonLabel>
          </IonItem>

          {debugMode && (
            <>
              <IonItemDivider>
                <IonLabel>{t("sidebar.debug")}</IonLabel>
              </IonItemDivider>
              <IonItem button routerLink="/bridge" routerDirection="root" onClick={closeMenu}>
                <IonIcon slot="start" icon={codeSlashOutline} />
                <IonLabel>{t("sidebar.bridge")}</IonLabel>
              </IonItem>
              <IonItem button routerLink="/preferences" routerDirection="root" onClick={closeMenu}>
                <IonIcon slot="start" icon={constructOutline} />
                <IonLabel>{t("sidebar.preferences")}</IonLabel>
              </IonItem>
              <IonItem button routerLink="/bridge/stream" routerDirection="root" onClick={closeMenu}>
                <IonIcon slot="start" icon={radioOutline} />
                <IonLabel>{t("sidebar.bridgeStream")}</IonLabel>
              </IonItem>
            </>
          )}

          <IonItemDivider />

          <IonItem button onClick={handleLogout}>
            <IonIcon slot="start" icon={logOutOutline} color="danger" />
            <IonLabel color="danger">{t("sidebar.logout")}</IonLabel>
          </IonItem>
        </IonList>
      </IonContent>

      <IonFooter>
        <IonToolbar>
          <div style={{ padding: "8px 16px", fontSize: "12px" }}>
            <IonNote>{user?.username ?? t("sidebar.notSignedIn")}</IonNote>
            <br />
            <IonNote
              onClick={handleVersionTap}
              style={{ cursor: "pointer", userSelect: "none" }}
            >
              v{appInfo?.appVersion ?? "..."} · {platformLabel}
            </IonNote>
          </div>
        </IonToolbar>
      </IonFooter>
    </IonMenu>
  );
}
