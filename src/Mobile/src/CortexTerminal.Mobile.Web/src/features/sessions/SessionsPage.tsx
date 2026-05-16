import {
  IonBadge,
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonMenuButton,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonSpinner,
  IonTitle,
  IonToolbar,
} from "@ionic/react";
import { addOutline, terminalOutline } from "ionicons/icons";
import { RouteComponentProps } from "react-router-dom";
import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";

function formatRelativeTime(isoDate: string, t: (key: string, opts?: Record<string, unknown>) => string): string {
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
import SessionInstallPrompt from "./SessionInstallPrompt";
import { useCreateSession } from "./useCreateSession";
import CreateSessionModal from "./CreateSessionModal";

const selectRecentSessions = (s: SessionState) => s.recentSessions;
const selectWorkers = (s: SessionState) => s.workers;
const selectSetSessions = (s: SessionState) => s.setSessions;
const selectSetWorkers = (s: SessionState) => s.setWorkers;

export default function SessionsPage({ history }: RouteComponentProps) {
  const { t } = useTranslation();
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);

  const recentSessions = useSessionStore(selectRecentSessions);
  const workers = useSessionStore(selectWorkers);
  const setSessions = useSessionStore(selectSetSessions);
  const setWorkers = useSessionStore(selectSetWorkers);

  const create = useCreateSession();

  // Load gateway state
  const loadGatewayState = useCallback(async (signal?: AbortSignal) => {
    const t0 = performance.now();
    try {
      console.log(`⏱ [sessions] listWorkers start`);
      const w = await terminalBridge.listWorkers();
      if (signal?.aborted) return;
      console.log(`⏱ [sessions] listWorkers done, ${w.length} workers, ${(performance.now() - t0).toFixed(0)}ms`);
      setWorkers(w);

      if (w.length === 0) {
        setSessions([]);
        setErrorMessage(null);
        return;
      }

      console.log(`⏱ [sessions] listSessions start`);
      const s = await terminalBridge.listSessions();
      if (signal?.aborted) return;
      console.log(`⏱ [sessions] listSessions done, ${s.length} sessions, total=${(performance.now() - t0).toFixed(0)}ms`);
      setSessions(s);
      setErrorMessage(null);
    } catch (error) {
      if (signal?.aborted) return;
      console.log(`⏱ [sessions] loadGatewayState FAIL after ${(performance.now() - t0).toFixed(0)}ms`);
      setWorkers([]);
      setSessions([]);
      setErrorMessage(error instanceof Error ? error.message : String(error));
    }
  }, [setSessions, setWorkers]);

  useEffect(() => {
    const ac = new AbortController();
    setIsLoading(true);
    // Delay to avoid racing with App-level bridge bootstrap calls
    // (5 concurrent fetch("/__hwvInvokeDotNet") from App.tsx useEffects)
    const timer = setTimeout(() => {
      void loadGatewayState(ac.signal).finally(() => {
        if (!ac.signal.aborted) setIsLoading(false);
      });
    }, 500);
    return () => { ac.abort(); clearTimeout(timer); };
  }, [loadGatewayState]);

  const handleRefresh = async (e: CustomEvent) => {
    await loadGatewayState();
    (e.detail as any).complete();
  };

  // Show install prompt when no sessions (regardless of workers)
  const showInstallPrompt = !isLoading && recentSessions.length === 0;

  return (
    <IonPage>
      <IonHeader translucent>
        <IonToolbar>
          <IonButtons slot="start">
            <IonMenuButton />
          </IonButtons>
          <IonTitle>{t("sessions.title")}</IonTitle>
          {!isLoading && workers.length > 0 && (
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
        {isLoading && (
          <IonItem lines="none">
            <IonSpinner slot="start" name="crescent" />
            <IonLabel>{t("common.loading")}</IonLabel>
          </IonItem>
        )}

        {errorMessage && (
          <IonItem color="danger">
            <IonLabel>{errorMessage}</IonLabel>
          </IonItem>
        )}

        {!isLoading && showInstallPrompt && (
          <SessionInstallPrompt />
        )}

        {!isLoading && !showInstallPrompt && recentSessions.length > 0 && (
          <>
            <IonList inset>
              {recentSessions.map((session) => (
                <IonItem
                  key={session.id}
                  button
                  detail
                  onClick={() => {
                    history.replace(`/sessions/${session.id}`);
                  }}
                >
                  <IonIcon slot="start" icon={terminalOutline} />
                  <IonLabel>
                    <h2>{session.title}</h2>
                    <p>{session.cwd ?? session.subtitle}{session.updatedAt ? ` · ${formatRelativeTime(session.updatedAt, t)}` : ""}</p>
                  </IonLabel>
                  <IonBadge
                    color={session.status === "running" ? "success" : "medium"}
                    slot="end"
                  >
                    {t(`sessions.status${session.status.charAt(0).toUpperCase()}${session.status.slice(1)}`)}
                  </IonBadge>
                </IonItem>
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
