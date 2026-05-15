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
  IonModal,
  IonPage,
  IonRefresher,
  IonRefresherContent,
  IonSpinner,
  IonTitle,
  IonToolbar,
} from "@ionic/react";
import { hardwareChipOutline } from "ionicons/icons";
import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { useSessionStore } from "../../store/sessionStore";
import { terminalBridge } from "../../bridge/modules/terminalBridge";
import type { WorkerSummary } from "../../schemas/sessionSchema";
import WorkerInstallPrompt from "./WorkerInstallPrompt";

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

export default function WorkersPage() {
  const { t } = useTranslation();
  const [isLoading, setIsLoading] = useState(false);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [selectedWorker, setSelectedWorker] = useState<WorkerSummary | null>(null);
  const workers = useSessionStore((state) => state.workers);
  const setWorkers = useSessionStore((state) => state.setWorkers);

  const loadWorkers = useCallback(async () => {
    try {
      const nextWorkers = await terminalBridge.listWorkers();
      setWorkers(nextWorkers);
      setErrorMessage(null);
    } catch (error) {
      setWorkers([]);
      setErrorMessage(error instanceof Error ? error.message : t("workers.loadFailed"));
    }
  }, [setWorkers]);

  useEffect(() => {
    let cancelled = false;
    setIsLoading(true);
    loadWorkers().finally(() => {
      if (!cancelled) setIsLoading(false);
    });
    return () => { cancelled = true; };
  }, [loadWorkers]);

  const handleRefresh = async (e: CustomEvent) => {
    await loadWorkers();
    (e.detail as any).complete();
  };

  return (
    <IonPage>
      <PageHeader title={t("workers.title")} defaultHref="/sessions" />
      <IonContent fullscreen>
        <IonRefresher slot="fixed" onIonRefresh={handleRefresh}>
          <IonRefresherContent />
        </IonRefresher>
        {isLoading && (
          <IonItem lines="none">
            <IonSpinner slot="start" name="crescent" />
            <IonLabel>{t("workers.loading")}</IonLabel>
          </IonItem>
        )}
        {errorMessage && (
          <IonItem color="danger">
            <IonLabel>{errorMessage}</IonLabel>
          </IonItem>
        )}
        {!isLoading && workers.length === 0 ? (
          <WorkerInstallPrompt />
        ) : (
          <IonList inset>
            {workers.map((worker) => (
              <IonItem
                key={worker.id}
                button
                detail
                onClick={() => setSelectedWorker(worker)}
              >
                <IonIcon slot="start" icon={hardwareChipOutline} />
                <IonLabel>
                  <h2>{worker.name}</h2>
                  <p>
                    {worker.activeTask}
                    {worker.lastSeenAtUtc ? ` · ${formatRelativeTime(worker.lastSeenAtUtc, t)}` : ""}
                  </p>
                </IonLabel>
                <IonBadge color={worker.status === "offline" ? "medium" : "success"}>
                  {worker.status === "offline" ? t("workers.statusOffline") : t("workers.statusOnline")}
                </IonBadge>
              </IonItem>
            ))}
          </IonList>
        )}

        <IonModal
          isOpen={!!selectedWorker}
          onDidDismiss={() => setSelectedWorker(null)}
          breakpoints={[0, 0.5]}
          initialBreakpoint={0.5}
        >
          <IonHeader>
            <IonToolbar>
              <IonTitle>{selectedWorker?.name ?? "Worker"}</IonTitle>
              <IonButtons slot="end">
                <IonButton onClick={() => setSelectedWorker(null)}>{t("workers.close")}</IonButton>
              </IonButtons>
            </IonToolbar>
          </IonHeader>
          <IonContent>
            {selectedWorker && (
              <IonList inset>
                <IonItem>
                  <IonLabel>{t("workers.status")}</IonLabel>
                  <IonBadge
                    slot="end"
                    color={
                      selectedWorker.status === "running"
                        ? "success"
                        : selectedWorker.status === "idle"
                          ? "primary"
                          : "medium"
                    }
                  >
                    {selectedWorker.status === "offline"
                      ? t("workers.statusOffline")
                      : t("workers.statusOnline")}
                  </IonBadge>
                </IonItem>
                {selectedWorker.hostname && (
                  <IonItem>
                    <IonLabel>{t("workers.hostname")}</IonLabel>
                    <IonLabel slot="end" style={{ textAlign: "right" }}>
                      {selectedWorker.hostname}
                    </IonLabel>
                  </IonItem>
                )}
                {selectedWorker.address && (
                  <IonItem>
                    <IonLabel>{t("workers.address")}</IonLabel>
                    <IonLabel slot="end" style={{ textAlign: "right" }}>
                      {selectedWorker.address}
                    </IonLabel>
                  </IonItem>
                )}
                {selectedWorker.operatingSystem && (
                  <IonItem>
                    <IonLabel>{t("workers.os")}</IonLabel>
                    <IonLabel slot="end" style={{ textAlign: "right" }}>
                      {selectedWorker.operatingSystem}
                    </IonLabel>
                  </IonItem>
                )}
                {selectedWorker.architecture && (
                  <IonItem>
                    <IonLabel>{t("workers.architecture")}</IonLabel>
                    <IonLabel slot="end" style={{ textAlign: "right" }}>
                      {selectedWorker.architecture}
                    </IonLabel>
                  </IonItem>
                )}
                {selectedWorker.version && (
                  <IonItem>
                    <IonLabel>{t("workers.version")}</IonLabel>
                    <IonLabel slot="end" style={{ textAlign: "right" }}>
                      {selectedWorker.version}
                    </IonLabel>
                  </IonItem>
                )}
                <IonItem>
                  <IonLabel>{t("workers.sessions")}</IonLabel>
                  <IonLabel slot="end" style={{ textAlign: "right" }}>
                    {selectedWorker.sessionCount ?? 0}
                  </IonLabel>
                </IonItem>
                {selectedWorker.lastSeenAtUtc && (
                  <IonItem>
                    <IonLabel>{t("workers.lastSeen")}</IonLabel>
                    <IonLabel slot="end" style={{ textAlign: "right" }}>
                      {formatRelativeTime(selectedWorker.lastSeenAtUtc, t)}
                    </IonLabel>
                  </IonItem>
                )}
              </IonList>
            )}
          </IonContent>
        </IonModal>
      </IonContent>
    </IonPage>
  );
}
