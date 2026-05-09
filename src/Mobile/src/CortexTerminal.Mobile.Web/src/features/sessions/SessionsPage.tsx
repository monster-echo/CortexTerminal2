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
  IonModal,
  IonPage,
  IonRadio,
  IonRadioGroup,
  IonRefresher,
  IonRefresherContent,
  IonSpinner,
  IonTitle,
  IonToolbar,
  useIonToast,
} from "@ionic/react";
import { addOutline, desktopOutline, terminalOutline } from "ionicons/icons";
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
import { useSessionStore } from "../../store/sessionStore";
import { terminalBridge } from "../../bridge/modules/terminalBridge";
import SessionInstallPrompt from "./SessionInstallPrompt";

export default function SessionsPage({ history }: RouteComponentProps) {
  const { t } = useTranslation();
  const [isLoading, setIsLoading] = useState(true);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [showCreateModal, setShowCreateModal] = useState(false);
  const [selectedWorkerId, setSelectedWorkerId] = useState<string | null>(null);

  const openCreateModal = () => {
    setSelectedWorkerId(workers[0]?.id ?? null);
    setShowCreateModal(true);
  };
  const [isCreating, setIsCreating] = useState(false);

  const recentSessions = useSessionStore((state) => state.recentSessions);
  const workers = useSessionStore((state) => state.workers);
  const setSessions = useSessionStore((state) => state.setSessions);
  const setWorkers = useSessionStore((state) => state.setWorkers);
  const touchSession = useSessionStore((state) => state.touchSession);
  const [presentToast] = useIonToast();

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


  const createSession = async () => {
    if (workers.length === 0) {
      presentToast({
        message: t("sessions.noWorkers"),
        duration: 3000,
        position: "bottom",
        color: "warning",
      });
      return;
    }

    // Measure the viewport to create the session at the correct PTY size
    const fontSize = 14;
    const charWidth = fontSize * 0.602; // typical monospace ratio
    const charHeight = fontSize * 1.2;  // line height
    const vpWidth = window.visualViewport?.width ?? window.innerWidth;
    const vpHeight = window.visualViewport?.height ?? window.innerHeight;
    const cols = Math.floor(vpWidth / charWidth);
    const rows = Math.floor((vpHeight - 56) / charHeight); // subtract toolbar

    setIsCreating(true);
    try {
      const session = await terminalBridge.createSession(
        cols,
        rows,
        selectedWorkerId ?? undefined,
      );
      touchSession(session);
      setShowCreateModal(false);
      setSelectedWorkerId(null);
      setErrorMessage(null);
      history.replace(`/sessions/${session.id}`);
    } catch (error) {
      presentToast({
        message: error instanceof Error ? error.message : String(error),
        duration: 3000,
        position: "bottom",
        color: "danger",
      });
    } finally {
      setIsCreating(false);
    }
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
              <IonButton onClick={openCreateModal}>
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
            <div style={{ padding: "8px 16px 0" }}>
              <IonButton
                expand="block"
                size="default"
                onClick={openCreateModal}
              >
                <IonIcon slot="start" icon={addOutline} />
                {t("sessions.createSession")}
              </IonButton>
            </div>
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
                    {session.status}
                  </IonBadge>
                </IonItem>
              ))}
            </IonList>
          </>
        )}

        {/* Create Session Modal */}
        <IonModal
          isOpen={showCreateModal}
          onDidDismiss={() => {
            setShowCreateModal(false);
            setSelectedWorkerId(null);
          }}
        >
          <IonHeader>
            <IonToolbar>
              <IonButtons slot="start">
                <IonButton onClick={() => setShowCreateModal(false)}>
                  {t("sessions.cancel")}
                </IonButton>
              </IonButtons>
              <IonTitle>{t("sessions.createSession")}</IonTitle>
              <IonButtons slot="end">
                <IonButton
                  strong
                  disabled={isCreating}
                  onClick={() => void createSession()}
                >
                  {isCreating ? t("sessions.creating") : t("sessions.create")}
                </IonButton>
              </IonButtons>
            </IonToolbar>
          </IonHeader>
          <IonContent>
            <IonList>
              <IonItem lines="none" style={{ paddingTop: 12, paddingBottom: 4 }}>
                <IonLabel>
                  <p>{t("sessions.selectWorker")}</p>
                </IonLabel>
              </IonItem>
              <IonRadioGroup
                value={selectedWorkerId}
                onIonChange={(e) => setSelectedWorkerId(e.detail.value)}
              >
                {workers.map((worker) => (
                  <IonItem key={worker.id}>
                    <IonRadio value={worker.id} labelPlacement="end">
                      <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                        <IonIcon
                          icon={desktopOutline}
                          style={{
                            fontSize: 16,
                            color:
                              worker.status === "running"
                                ? "var(--ion-color-success)"
                                : "var(--ion-color-medium)",
                          }}
                        />
                        <div>
                          <div style={{ fontWeight: 500 }}>{worker.name}</div>
                          {worker.hostname && (
                            <div style={{ fontSize: 12, color: "var(--ion-color-medium)" }}>
                              {worker.hostname}
                              {worker.operatingSystem ? ` · ${worker.operatingSystem}` : ""}
                            </div>
                          )}
                        </div>
                      </div>
                    </IonRadio>
                  </IonItem>
                ))}
              </IonRadioGroup>
            </IonList>
          </IonContent>
        </IonModal>
      </IonContent>
    </IonPage>
  );
}
