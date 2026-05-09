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
  IonItemDivider,
} from "@ionic/react";
import {
  settingsOutline,
  terminalOutline,
  ellipsisHorizontalOutline,
  hardwareChipOutline,
} from "ionicons/icons";
import { useTranslation } from "react-i18next";
import { useAppStore } from "../store/appStore";
import { useAuthStore } from "../store/authStore";
import { useSessionStore } from "../store/sessionStore";
import logoSvg from "../assets/logo.svg";

export default function AppSidebar() {
  const { t } = useTranslation();
  const appInfo = useAppStore((s) => s.appInfo);
  const user = useAuthStore((s) => s.user);
  const recentSessions = useSessionStore((s) => s.recentSessions);
  const currentSessionId = useSessionStore((s) => s.currentSessionId);
  const setCurrentSession = useSessionStore((s) => s.setCurrentSession);

  const menuRef = useRef<HTMLIonMenuElement>(null);

  const closeMenu = () => {
    menuRef.current?.close();
  };

  return (
    <IonMenu ref={menuRef} side="start" menuId="main-menu" contentId="main-content">
      <IonHeader>
        <IonToolbar>
          <div style={{ display: "flex", alignItems: "center", gap: 10, paddingLeft: 16, height: "100%" }}>
            <img src={logoSvg} alt="" style={{ width: 32, height: 32 }} />
            <IonTitle style={{ padding: 0 }}>{t("sidebar.title")}</IonTitle>
          </div>
        </IonToolbar>
      </IonHeader>

      <IonContent>
        <IonList>
          <IonItemDivider>
            <IonLabel>Sessions</IonLabel>
          </IonItemDivider>
          {recentSessions.length === 0 && (
            <IonItem routerLink="/sessions" routerDirection="root" onClick={closeMenu}>
              <IonIcon slot="start" icon={terminalOutline} />
              <IonLabel>
                <h2>No sessions</h2>
                <p>Tap to set up your first session</p>
              </IonLabel>
            </IonItem>
          )}
          {recentSessions.slice(0, 5).map((session) => (
            <IonItem
              key={session.id}
              button
              routerLink={`/sessions/${session.id}`}
              routerDirection="root"
              color={session.id === currentSessionId ? "light" : undefined}
              onClick={() => {
                setCurrentSession(session.id);
                closeMenu();
              }}
            >
              <IonIcon slot="start" icon={terminalOutline} />
              <IonLabel>
                <h2>{session.title}</h2>
                <p>{session.cwd ?? session.subtitle}</p>
              </IonLabel>
            </IonItem>
          ))}
          {recentSessions.length > 5 && (
            <IonItem button routerLink="/sessions" routerDirection="root" onClick={closeMenu}>
              <IonIcon slot="start" icon={ellipsisHorizontalOutline} />
              <IonLabel>More</IonLabel>
            </IonItem>
          )}

          <IonItemDivider />

          <IonItem button routerLink="/workers" routerDirection="root" onClick={closeMenu}>
            <IonIcon slot="start" icon={hardwareChipOutline} />
            <IonLabel>Workers</IonLabel>
          </IonItem>
          <IonItem button routerLink="/settings" routerDirection="root" onClick={closeMenu}>
            <IonIcon slot="start" icon={settingsOutline} />
            <IonLabel>{t("sidebar.settings")}</IonLabel>
          </IonItem>
        </IonList>
      </IonContent>

      <IonFooter>
        <IonToolbar>
          <IonItem lines="none" routerLink="/settings" routerDirection="root" onClick={closeMenu}>
            <div
              slot="start"
              style={{
                width: 32,
                height: 32,
                borderRadius: "50%",
                background: "var(--ion-color-primary)",
                color: "#fff",
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                fontWeight: 600,
                fontSize: 14,
              }}
            >
              {(user?.username ?? "?")[0].toUpperCase()}
            </div>
            <IonLabel>
              <h3>{user?.username ?? t("sidebar.notSignedIn")}</h3>
              <p>v{appInfo?.appVersion ?? "..."}</p>
            </IonLabel>
          </IonItem>
        </IonToolbar>
      </IonFooter>
    </IonMenu>
  );
}
