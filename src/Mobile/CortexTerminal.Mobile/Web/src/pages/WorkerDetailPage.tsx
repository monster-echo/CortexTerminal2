import { useEffect, useState } from "react"
import { useHistory } from "react-router-dom"
import {
  IonPage,
  IonHeader,
  IonToolbar,
  IonTitle,
  IonContent,
  IonButton,
  IonIcon,
  IonCard,
  IonCardContent,
  IonList,
  IonItem,
  IonLabel,
  IonBadge,
  IonSkeletonText,
  IonText,
} from "@ionic/react"
import { arrowBackOutline, cloudUploadOutline } from "ionicons/icons"
import type { ConsoleApi, WorkerDetail } from "../services/consoleApi"

const statusColors: Record<string, string> = {
  live: "#10b981",
  detached: "#f59e0b",
  exited: "#ef4444",
  expired: "#71717a",
}

const statusBadgeColor: Record<string, string> = {
  live: "success",
  detached: "warning",
  exited: "danger",
  expired: "medium",
}

export function WorkerDetailPage({
  api,
  workerId,
}: {
  api: ConsoleApi
  workerId: string
}) {
  const history = useHistory()
  const [worker, setWorker] = useState<WorkerDetail | null>(null)
  const [isLoading, setIsLoading] = useState(true)
  const [isUpgrading, setIsUpgrading] = useState(false)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true
    setIsLoading(true)
    setWorker(null)
    setErrorMessage(null)

    api
      .getWorker(workerId)
      .then((value) => {
        if (!isActive) return
        setWorker(value)
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(
          error instanceof Error ? error.message : "Could not load worker.",
        )
      })
      .finally(() => {
        if (isActive) setIsLoading(false)
      })

    return () => {
      isActive = false
    }
  }, [api, workerId])

  const handleUpgrade = async () => {
    setIsUpgrading(true)
    try {
      await api.upgradeWorker(workerId)
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Upgrade failed.",
      )
    } finally {
      setIsUpgrading(false)
    }
  }

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonButton
            slot="start"
            fill="clear"
            onClick={() => history.push("/workers")}
          >
            <IonIcon icon={arrowBackOutline} slot="icon-only" />
          </IonButton>
          <IonTitle>
            {worker?.name ?? workerId}
          </IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        {errorMessage && (
          <div style={{ padding: "0 16px", marginTop: 8 }}>
            <IonText color="danger">
              <p style={{ fontSize: 13 }}>{errorMessage}</p>
            </IonText>
          </div>
        )}

        {isLoading ? (
          <div style={{ padding: 16 }}>
            <IonCard>
              <IonCardContent>
                <IonSkeletonText animated style={{ height: 32 }} />
              </IonCardContent>
            </IonCard>
            {[1, 2].map((i) => (
              <IonItem key={i}>
                <IonSkeletonText animated style={{ height: 20 }} />
              </IonItem>
            ))}
          </div>
        ) : worker ? (
          <>
            <IonCard style={{ margin: 16 }}>
              <IonCardContent>
                <div
                  style={{
                    display: "flex",
                    alignItems: "center",
                    gap: 12,
                    marginBottom: 12,
                  }}
                >
                  <span
                    style={{
                      width: 12,
                      height: 12,
                      borderRadius: "50%",
                      backgroundColor: worker.isOnline ? "#10b981" : "#71717a",
                      flexShrink: 0,
                    }}
                  />
                  <div style={{ flex: 1 }}>
                    <h2
                      style={{
                        fontSize: 18,
                        fontWeight: 700,
                        margin: 0,
                      }}
                    >
                      {worker.name}
                    </h2>
                    <p
                      style={{
                        fontFamily: "monospace",
                        fontSize: 11,
                        color: "var(--ion-color-medium)",
                        margin: 0,
                      }}
                    >
                      {worker.workerId}
                    </p>
                  </div>
                  <IonBadge
                    color={worker.isOnline ? "success" : "medium"}
                  >
                    {worker.isOnline ? "Online" : "Offline"}
                  </IonBadge>
                </div>

                <div
                  style={{
                    display: "grid",
                    gridTemplateColumns: "1fr 1fr",
                    gap: 8,
                    fontSize: 12,
                  }}
                >
                  <div>
                    <IonText color="medium">
                      <span>Sessions</span>
                    </IonText>
                    <p style={{ fontWeight: 600, margin: 0 }}>
                      {worker.sessionCount}
                    </p>
                  </div>
                  <div>
                    <IonText color="medium">
                      <span>Last seen</span>
                    </IonText>
                    <p style={{ fontWeight: 600, margin: 0 }}>
                      {new Date(worker.lastSeenAt).toLocaleTimeString([], {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </p>
                  </div>
                  {worker.hostname && (
                    <div>
                      <IonText color="medium">
                        <span>Hostname</span>
                      </IonText>
                      <p style={{ fontWeight: 600, margin: 0 }}>
                        {worker.hostname}
                      </p>
                    </div>
                  )}
                  {worker.version && (
                    <div>
                      <IonText color="medium">
                        <span>Version</span>
                      </IonText>
                      <p style={{ fontWeight: 600, margin: 0 }}>
                        {worker.version}
                      </p>
                    </div>
                  )}
                </div>

                <IonButton
                  expand="block"
                  fill="outline"
                  size="small"
                  disabled={isUpgrading}
                  onClick={() => void handleUpgrade()}
                  style={{ marginTop: 16 }}
                >
                  <IonIcon icon={cloudUploadOutline} slot="start" />
                  {isUpgrading ? "Upgrading..." : "Upgrade Worker"}
                </IonButton>
              </IonCardContent>
            </IonCard>

            <div style={{ padding: "0 16px" }}>
              <p
                style={{
                  fontSize: 14,
                  fontWeight: 600,
                  marginBottom: 8,
                }}
              >
                Hosted Sessions
              </p>
            </div>

            {worker.sessions.length === 0 ? (
              <div style={{ padding: "0 16px" }}>
                <IonText color="medium">
                  <p style={{ fontSize: 13, textAlign: "center" }}>
                    No sessions on this worker
                  </p>
                </IonText>
              </div>
            ) : (
              <IonList>
                {worker.sessions.map((session) => (
                  <IonItem
                    key={session.sessionId}
                    button
                    onClick={() =>
                      history.push(`/sessions/${session.sessionId}`)
                    }
                  >
                    <span
                      style={{
                        width: 10,
                        height: 10,
                        borderRadius: "50%",
                        backgroundColor:
                          statusColors[session.status] ?? "#71717a",
                        marginRight: 12,
                        flexShrink: 0,
                      }}
                    />
                    <IonLabel>
                      <h3
                        style={{
                          fontFamily: "monospace",
                          fontSize: 12,
                        }}
                      >
                        {session.sessionId}
                      </h3>
                      <p>
                        {new Date(session.lastActivityAt).toLocaleTimeString(
                          [],
                          { hour: "2-digit", minute: "2-digit" },
                        )}
                      </p>
                    </IonLabel>
                    <IonBadge
                      slot="end"
                      color={statusBadgeColor[session.status] ?? "medium"}
                    >
                      {session.status}
                    </IonBadge>
                  </IonItem>
                ))}
              </IonList>
            )}
          </>
        ) : null}
      </IonContent>
    </IonPage>
  )
}
