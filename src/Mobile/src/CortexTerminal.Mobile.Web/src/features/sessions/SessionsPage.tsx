import {
  IonBadge,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonItemOption,
  IonItemOptions,
  IonItemSliding,
  IonLabel,
  IonList,
  IonMenuButton,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonSkeletonText,
  IonTitle,
  IonToolbar,
  useIonAlert,
  useIonToast,
} from "@ionic/react";
import { addOutline, createOutline, terminalOutline, trashOutline } from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useCallback, useState } from "react";
import { useTranslation } from "react-i18next";

function formatRelativeTime(
  isoDate: string,
  t: (key: string, opts?: Record<string, unknown>) => string,
): string {
  const diff = Date.now() - new Date(isoDate).getTime();
  const seconds = Math.floor(diff / 1000);
  if (seconds < 60) return t("sessions.justNow");
  const minutes = Math.floor(seconds / 60);
  if (minutes < 60) return t("sessions.minutesAgo", { count: minutes });
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return t("sessions.hoursAgo", { count: hours });
  const days = Math.floor(hours / 24);
  if (days < 30) return t("sessions.daysAgo", { count: days });
  return new Date(isoDate).toLocaleDateString();
}
import { useSessionStore, type SessionState } from "../../store/sessionStore";
import { terminalBridge } from "../../bridge/modules/terminalBridge";
import { nativeBridge } from "../../bridge/nativeBridge";
import SessionInstallPrompt from "./SessionInstallPrompt";
import { useCreateSession } from "./useCreateSession";
import CreateSessionModal from "./CreateSessionModal";

const selectRecentSessions = (s: SessionState) => s.recentSessions;
const selectWorkers = (s: SessionState) => s.workers;
const selectIsGatewayLoaded = (s: SessionState) => s.isGatewayLoaded;
const selectSetSessions = (s: SessionState) => s.setSessions;
const selectSetWorkers = (s: SessionState) => s.setWorkers;
const selectRemoveSession = (s: SessionState) => s.removeSession;
const selectRenameSession = (s: SessionState) => s.renameSession;

export default function SessionsPage({ history }: RouteComponentProps) {
  const { t } = useTranslation();
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const recentSessions = useSessionStore(selectRecentSessions);
  const workers = useSessionStore(selectWorkers);
  const isGatewayLoaded = useSessionStore(selectIsGatewayLoaded);
  const setSessions = useSessionStore(selectSetSessions);
  const setWorkers = useSessionStore(selectSetWorkers);
  const removeSession = useSessionStore(selectRemoveSession);
  const renameSession = useSessionStore(selectRenameSession);
  const [presentToast] = useIonToast();
  const [presentRenameAlert] = useIonAlert();

  const create = useCreateSession();

  // Refresh gateway state (used by pull-to-refresh only; App.tsx preloads on mount)
  const refreshGatewayState = useCallback(async () => {
    try {
      const [w, s] = await Promise.all([
        terminalBridge.listWorkers(),
        terminalBridge.listSessions(),
      ]);
      setWorkers(w);
      setSessions(s);
      setErrorMessage(null);
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : String(error));
    }
  }, [setSessions, setWorkers]);

  const handleRefresh = async (e: CustomEvent) => {
    await refreshGatewayState();
    (e.detail as any).complete();
  };

  // Show install prompt when no sessions (regardless of workers)
  const showInstallPrompt = isGatewayLoaded && recentSessions.length === 0;

  return (
    <IonPage>
      <IonHeader translucent>
        <IonToolbar>
          <IonButtons slot="start">
            <IonMenuButton />
          </IonButtons>
          <IonTitle>{t("sessions.title")}</IonTitle>
          {isGatewayLoaded && workers.length > 0 && (
            <IonButtons slot="end">
              <IonButton onClick={create.openModal}>
                <IonIcon slot="icon-only" icon={addOutline} />
              </IonButton>
            </IonButtons>
          )}
        </IonToolbar>
      </IonHeader>
      <IonContent fullscreen>
        <IonRefresher slot="fixed" onIonRefresh={handleRefresh}>
          <IonRefresherContent />
        </IonRefresher>
        {!isGatewayLoaded && (
          <IonList inset>
            {[0, 1, 2].map((i) => (
              <IonItem key={i}>
                <IonSkeletonText
                  animated
                  style={{
                    width: "20px",
                    height: "20px",
                    borderRadius: "50%",
                    minWidth: "20px",
                  }}
                  slot="start"
                />
                <IonLabel>
                  <h2>
                    <IonSkeletonText
                      animated
                      style={{ width: "60%", height: "14px" }}
                    />
                  </h2>
                  <p>
                    <IonSkeletonText
                      animated
                      style={{ width: "40%", height: "12px" }}
                    />
                  </p>
                </IonLabel>
                <IonSkeletonText
                  animated
                  style={{ width: "48px", height: "18px", borderRadius: "8px" }}
                  slot="end"
                />
              </IonItem>
            ))}
          </IonList>
        )}

        {errorMessage && (
          <IonItem color="danger">
            <IonLabel>{errorMessage}</IonLabel>
          </IonItem>
        )}

        {isGatewayLoaded && showInstallPrompt && <SessionInstallPrompt />}

        {isGatewayLoaded && !showInstallPrompt && recentSessions.length > 0 && (
          <>
            <IonList inset>
              {recentSessions.map((session) => (
                <IonItemSliding key={session.id}>
                  <IonItem
                    button
                    detail
                    onClick={() => {
                      history.replace(`/sessions/${session.id}`);
                    }}
                  >
                    <IonIcon slot="start" icon={terminalOutline} />
                    <IonLabel>
                      <h2>{session.title}</h2>
                      <p>
                        {session.cwd ?? session.subtitle}
                        {session.updatedAt
                          ? ` · ${formatRelativeTime(session.updatedAt, t)}`
                          : ""}
                      </p>
                    </IonLabel>
                    <IonBadge
                      color={
                        session.status === "running" ? "success" : "medium"
                      }
                      slot="end"
                    >
                      {t(
                        `sessions.status${session.status.charAt(0).toUpperCase()}${session.status.slice(1)}`,
                      )}
                    </IonBadge>
                  </IonItem>
                  <IonItemOptions
                    side="end"
                    style={{ background: "transparent" }}
                  >
                    <IonItemOption
                      color="primary"
                      style={{
                        margin: "4px 4px 4px 0",
                        borderRadius: "8px",
                        padding: "0 16px",
                      }}
                      onClick={() => {
                        presentRenameAlert({
                          header: t("sessions.rename"),
                          inputs: [
                            {
                              name: "name",
                              value: session.title,
                              placeholder: t("sessions.namePlaceholder"),
                            },
                          ],
                          buttons: [
                            { text: t("sessions.cancel"), role: "cancel" },
                            {
                              text: t("sessions.create"),
                              handler: async (data: Record<string, string>) => {
                                const newName = data.name?.trim();
                                if (newName && newName !== session.title) {
                                  try {
                                    await terminalBridge.renameSession(session.id, newName);
                                    renameSession(session.id, newName);
                                  } catch (e) {
                                    presentToast({
                                      message: e instanceof Error ? e.message : String(e),
                                      duration: 3000,
                                      position: "bottom",
                                      color: "danger",
                                    });
                                  }
                                }
                              },
                            },
                          ],
                        });
                      }}
                    >
                      <IonIcon icon={createOutline} slot="icon-only" />
                    </IonItemOption>
                    <IonItemOption
                      color="danger"
                      expandable
                      style={{
                        margin: "4px 8px 4px 0",
                        borderRadius: "8px",
                        padding: "0 16px",
                      }}
                      onClick={async () => {
                        try {
                          await terminalBridge.deleteSession(session.id);
                          removeSession(session.id);
                          nativeBridge.trackEvent("session_delete");
                        } catch (e) {
                          presentToast({
                            message: e instanceof Error ? e.message : String(e),
                            duration: 3000,
                            position: "bottom",
                            color: "danger",
                          });
                        }
                      }}
                    >
                      <IonIcon icon={trashOutline} slot="icon-only" />
                    </IonItemOption>
                  </IonItemOptions>
                </IonItemSliding>
              ))}
            </IonList>
          </>
        )}

        <CreateSessionModal
          isOpen={create.showModal}
          onClose={create.closeModal}
          onlineWorkers={create.onlineWorkers}
          selectedWorkerId={create.selectedWorkerId}
          onSelectWorker={create.setSelectedWorkerId}
          isCreating={create.isCreating}
          onCreate={create.createSession}
        />
      </IonContent>
    </IonPage>
  );
}
