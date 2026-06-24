import {
  IonAlert,
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
  IonSkeletonText,
  IonTitle,
  IonToolbar,
} from "@ionic/react";
import { arrowUpCircleOutline, hardwareChipOutline } from "ionicons/icons";
import { useCallback, useEffect, useRef, useState } from "react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { feedbackBridge } from "../../bridge/modules/feedbackBridge";
import { terminalBridge } from "../../bridge/modules/terminalBridge";
import { useSessionStore, type SessionState } from "../../store/sessionStore";
import type { WorkerSummary } from "../../schemas/sessionSchema";
import WorkerInstallPrompt from "./WorkerInstallPrompt";

const selectWorkers = (s: SessionState) => s.workers;
const selectIsGatewayLoaded = (s: SessionState) => s.isGatewayLoaded;
const selectSetWorkers = (s: SessionState) => s.setWorkers;
const selectLatestWorkerVersion = (s: SessionState) => s.latestWorkerVersion;

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

function normalizeVersion(version: string): string {
  return version.replace(/(\.0)+$/, "");
}

const UPGRADE_POLL_INTERVAL_MS = 3000;
const UPGRADE_POLL_MAX_ATTEMPTS = 5;

export default function WorkersPage() {
  const { t } = useTranslation();
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [selectedWorker, setSelectedWorker] = useState<WorkerSummary | null>(null);
  const [showUpgradeAlert, setShowUpgradeAlert] = useState(false);
  const [isUpgrading, setIsUpgrading] = useState(false);
  const workers = useSessionStore(selectWorkers);
  const isGatewayLoaded = useSessionStore(selectIsGatewayLoaded);
  const setWorkers = useSessionStore(selectSetWorkers);
  const latestWorkerVersion = useSessionStore(selectLatestWorkerVersion);
  const pollingRef = useRef<ReturnType<typeof setInterval> | null>(null);

  const stopPolling = useCallback(() => {
    if (pollingRef.current !== null) {
      clearInterval(pollingRef.current);
      pollingRef.current = null;
    }
  }, []);

  useEffect(() => () => stopPolling(), [stopPolling]);

  const canUpgrade = useCallback((worker: WorkerSummary | null): boolean => {
    if (!worker) return false;
    if (worker.status === "offline") return false;
    if (!worker.version || !latestWorkerVersion) return false;
    return normalizeVersion(worker.version) !== normalizeVersion(latestWorkerVersion);
  }, [latestWorkerVersion]);

  const refreshWorkers = useCallback(async () => {
    try {
      const nextWorkers = await terminalBridge.listWorkers();
      setWorkers(nextWorkers);
      setErrorMessage(null);
      return nextWorkers;
    } catch (error) {
      setErrorMessage(error instanceof Error ? error.message : t("workers.loadFailed"));
      return null;
    }
  }, [setWorkers, t]);

  const startUpgradePolling = useCallback((workerId: string, targetVersion: string) => {
    stopPolling();
    let attempts = 0;
    pollingRef.current = setInterval(async () => {
      attempts += 1;
      const next = await refreshWorkers();
      if (!next) return;
      const updated = next.find((w) => (w.workerId ?? w.id) === workerId);
      if (updated?.version && normalizeVersion(updated.version) === normalizeVersion(targetVersion)) {
        stopPolling();
        return;
      }
      if (attempts >= UPGRADE_POLL_MAX_ATTEMPTS) {
        stopPolling();
      }
    }, UPGRADE_POLL_INTERVAL_MS);
  }, [refreshWorkers, stopPolling]);

  const doUpgrade = async () => {
    const worker = selectedWorker;
    if (!worker) return;
    const workerId = worker.workerId ?? worker.id;
    setIsUpgrading(true);
    await feedbackBridge.showSnackbarWithOptions(
      t("workers.upgrade.sending", { name: worker.name }),
      undefined,
      "indefinite",
    );
    try {
      const result = await terminalBridge.upgradeWorker(workerId);
      await feedbackBridge.dismissSnackbar();
      await feedbackBridge.haptics("success");
      setSelectedWorker(null);
      if (result.message.toLowerCase().includes("already")) {
        await feedbackBridge.showToast(t("workers.upgrade.upToDate"));
      } else {
        await feedbackBridge.showToast(t("workers.upgrade.sent"));
        startUpgradePolling(workerId, result.targetVersion ?? latestWorkerVersion ?? "");
      }
    } catch (error) {
      await feedbackBridge.dismissSnackbar();
      await feedbackBridge.haptics("error");
      const message = error instanceof Error ? error.message : String(error);
      await feedbackBridge.showToast(t("workers.upgrade.failed", { message }));
    } finally {
      setIsUpgrading(false);
    }
  };

  const handleRefresh = async (e: CustomEvent) => {
    await refreshWorkers();
    (e.detail as any).complete();
  };

  return (
    <IonPage>
      <PageHeader title={t("workers.title")} defaultHref="/sessions" />
      <IonContent fullscreen>
        <IonRefresher slot="fixed" onIonRefresh={handleRefresh}>
          <IonRefresherContent />
        </IonRefresher>
        {!isGatewayLoaded && (
          <IonList inset>
            {[0, 1, 2].map((i) => (
              <IonItem key={i}>
                <IonSkeletonText animated style={{ width: "20px", height: "20px", borderRadius: "50%", minWidth: "20px" }} slot="start" />
                <IonLabel>
                  <h2><IonSkeletonText animated style={{ width: "60%", height: "14px" }} /></h2>
                  <p><IonSkeletonText animated style={{ width: "40%", height: "12px" }} /></p>
                </IonLabel>
                <IonSkeletonText animated style={{ width: "48px", height: "18px", borderRadius: "8px" }} slot="end" />
              </IonItem>
            ))}
          </IonList>
        )}
        {errorMessage && (
          <IonItem color="danger">
            <IonLabel>{errorMessage}</IonLabel>
          </IonItem>
        )}
        {isGatewayLoaded && workers.length === 0 ? (
          <WorkerInstallPrompt />
        ) : (
          <IonList inset>
            {workers.map((worker) => {
              const upgradable = canUpgrade(worker);
              return (
                <IonItem
                  key={worker.id}
                  button
                  detail
                  data-analytics-id="workers_item"
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
                  {upgradable && (
                    <IonBadge slot="end" color="warning" data-analytics-id="workers_update_available">
                      <IonIcon icon={arrowUpCircleOutline} style={{ verticalAlign: "-2px", marginRight: "4px" }} />
                      {t("workers.updateAvailable")}
                    </IonBadge>
                  )}
                  <IonBadge slot="end" color={worker.status === "offline" ? "medium" : "success"}>
                    {worker.status === "offline" ? t("workers.statusOffline") : t("workers.statusOnline")}
                  </IonBadge>
                </IonItem>
              );
            })}
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
              <IonTitle>{selectedWorker?.name ?? t("workers.title")}</IonTitle>
              <IonButtons slot="end">
                <IonButton onClick={() => setSelectedWorker(null)} data-analytics-id="workers_detail_close">{t("workers.close")}</IonButton>
              </IonButtons>
            </IonToolbar>
          </IonHeader>
          <IonContent>
            {selectedWorker && (
              <>
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
                {canUpgrade(selectedWorker) && latestWorkerVersion && (
                  <div style={{ padding: "0 16px 16px" }}>
                    <IonButton
                      expand="block"
                      color="primary"
                      disabled={isUpgrading}
                      data-analytics-id="workers_upgrade_button"
                      onClick={() => setShowUpgradeAlert(true)}
                    >
                      <IonIcon slot="start" icon={arrowUpCircleOutline} />
                      {t("workers.upgrade.button", { version: latestWorkerVersion })}
                    </IonButton>
                  </div>
                )}
              </>
            )}
          </IonContent>
        </IonModal>

        <IonAlert
          isOpen={showUpgradeAlert}
          onDidDismiss={() => setShowUpgradeAlert(false)}
          header={t("workers.upgrade.title")}
          message={selectedWorker && latestWorkerVersion
            ? t("workers.upgrade.description", {
                name: selectedWorker.name,
                currentVersion: selectedWorker.version ?? "?",
                targetVersion: latestWorkerVersion,
              })
            : ""}
          buttons={[
            { text: t("workers.upgrade.cancel"), role: "cancel" },
            {
              text: t("workers.upgrade.confirm"),
              handler: () => { void doUpgrade(); },
            },
          ]}
        />
      </IonContent>
    </IonPage>
  );
}
