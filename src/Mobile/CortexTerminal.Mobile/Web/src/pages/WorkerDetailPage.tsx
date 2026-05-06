import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
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
  IonGrid,
  IonRow,
  IonCol,
  IonSkeletonText,
  IonText,
} from "@ionic/react"
import { arrowBackOutline, cloudUploadOutline } from "ionicons/icons"
import type { ConsoleApi, WorkerDetail } from "../services/consoleApi"
import { StatusDot } from "../components/StatusDot"

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
  const { t } = useTranslation()
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
          error instanceof Error ? error.message : t('workers.loadErrorDetail'),
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
        error instanceof Error ? error.message : t('workers.upgradeFailed'),
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
          <div className="ion-padding-horizontal ion-margin-top">
            <IonText color="danger">
              <p style={{ fontSize: 13 }}>{errorMessage}</p>
            </IonText>
          </div>
        )}

        {isLoading ? (
          <div className="ion-padding">
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
            <IonCard className="ion-margin">
              <IonCardContent>
                <div style={{ display: "flex", alignItems: "center", gap: 12, marginBottom: 12 }}>
                  <StatusDot status={worker.isOnline ? "online" : "offline"} />
                  <div style={{ flex: 1 }}>
                    <h2 style={{ fontSize: 18, fontWeight: 700, margin: 0 }}>
                      {worker.name}
                    </h2>
                    <p className="mono" style={{ fontSize: 11, color: "var(--ion-color-medium)", margin: 0 }}>
                      {worker.workerId}
                    </p>
                  </div>
                  <IonBadge color={worker.isOnline ? "success" : "medium"}>
                    {worker.isOnline ? t('workers.online') : t('workers.offline')}
                  </IonBadge>
                </div>

                <IonGrid>
                  <IonRow>
                    <IonCol size="6">
                      <IonText color="medium"><span>{t('workers.sessions')}</span></IonText>
                      <p style={{ fontWeight: 600, margin: 0 }}>{worker.sessionCount}</p>
                    </IonCol>
                    <IonCol size="6">
                      <IonText color="medium"><span>{t('workers.lastSeen')}</span></IonText>
                      <p style={{ fontWeight: 600, margin: 0 }}>
                        {new Date(worker.lastSeenAt).toLocaleTimeString([], {
                          hour: "2-digit",
                          minute: "2-digit",
                        })}
                      </p>
                    </IonCol>
                  </IonRow>
                  {worker.hostname && (
                    <IonRow>
                      <IonCol size="6">
                        <IonText color="medium"><span>{t('workers.hostname')}</span></IonText>
                        <p style={{ fontWeight: 600, margin: 0 }}>{worker.hostname}</p>
                      </IonCol>
                      {worker.version && (
                        <IonCol size="6">
                          <IonText color="medium"><span>{t('workers.version')}</span></IonText>
                          <p style={{ fontWeight: 600, margin: 0 }}>{worker.version}</p>
                        </IonCol>
                      )}
                    </IonRow>
                  )}
                  {!worker.hostname && worker.version && (
                    <IonRow>
                      <IonCol size="6">
                        <IonText color="medium"><span>{t('workers.version')}</span></IonText>
                        <p style={{ fontWeight: 600, margin: 0 }}>{worker.version}</p>
                      </IonCol>
                    </IonRow>
                  )}
                </IonGrid>

                <IonButton
                  expand="block"
                  fill="outline"
                  size="small"
                  className="ion-margin-top"
                  disabled={isUpgrading}
                  onClick={() => void handleUpgrade()}
                >
                  <IonIcon icon={cloudUploadOutline} slot="start" />
                  {isUpgrading ? t('workers.upgrading') : t('workers.upgradeWorker')}
                </IonButton>
              </IonCardContent>
            </IonCard>

            <div className="ion-padding-horizontal">
              <p className="section-label">{t('workers.hostedSessions')}</p>
            </div>

            {worker.sessions.length === 0 ? (
              <div className="ion-padding-horizontal">
                <IonText color="medium">
                  <p className="ion-text-center" style={{ fontSize: 13 }}>{t('workers.noSessions')}</p>
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
                    <StatusDot status={session.status} />
                    <IonLabel>
                      <h3 className="mono">{session.sessionId}</h3>
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
