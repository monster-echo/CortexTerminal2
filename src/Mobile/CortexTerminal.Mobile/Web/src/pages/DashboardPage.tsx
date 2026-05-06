import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { useHistory } from "react-router-dom"
import {
  IonPage,
  IonHeader,
  IonToolbar,
  IonTitle,
  IonContent,
  IonCard,
  IonCardContent,
  IonGrid,
  IonRow,
  IonCol,
  IonList,
  IonItem,
  IonLabel,
  IonBadge,
  IonIcon,
  IonSkeletonText,
  IonText,
  IonButton,
} from "@ionic/react"
import {
  pulseOutline,
  desktopOutline,
  serverOutline,
  timeOutline,
} from "ionicons/icons"
import type { ConsoleApi, SessionSummary } from "../services/consoleApi"
import { StatusDot } from "../components/StatusDot"

const statusBadgeColor: Record<string, string> = {
  live: "success",
  detached: "warning",
  exited: "danger",
  expired: "medium",
}

export function DashboardPage({ api }: { api: ConsoleApi }) {
  const { t } = useTranslation()
  const history = useHistory()
  const [sessions, setSessions] = useState<SessionSummary[]>([])
  const [workerCount, setWorkerCount] = useState(0)
  const [isLoading, setIsLoading] = useState(true)

  useEffect(() => {
    let isActive = true
    Promise.all([api.listSessions(), api.listWorkers()])
      .then(([sessionList, workerList]) => {
        if (!isActive) return
        setSessions(sessionList)
        setWorkerCount(workerList.length)
      })
      .catch(() => {})
      .finally(() => {
        if (isActive) setIsLoading(false)
      })
    return () => {
      isActive = false
    }
  }, [api])

  const liveCount = sessions.filter((s) => s.status === "live").length
  const detachedCount = sessions.filter((s) => s.status === "detached").length

  const stats = [
    { label: t('dashboard.active'), value: liveCount, icon: pulseOutline, color: "success" as const },
    { label: t('dashboard.detached'), value: detachedCount, icon: desktopOutline, color: "warning" as const },
    { label: t('dashboard.workers'), value: workerCount, icon: serverOutline, color: "primary" as const },
    { label: t('dashboard.total'), value: sessions.length, icon: timeOutline, color: "medium" as const },
  ]

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonTitle>{t('dashboard.title')}</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        {isLoading ? (
          <div className="ion-padding">
            <IonGrid>
              <IonRow>
                {[1, 2, 3, 4].map((i) => (
                  <IonCol size="6" key={i}>
                    <IonCard>
                      <IonCardContent>
                        <IonSkeletonText animated style={{ height: 80 }} />
                      </IonCardContent>
                    </IonCard>
                  </IonCol>
                ))}
              </IonRow>
            </IonGrid>
          </div>
        ) : (
          <div className="ion-padding">
            <IonGrid>
              <IonRow>
                {stats.map((stat) => (
                  <IonCol size="6" key={stat.label}>
                    <IonCard>
                      <IonCardContent>
                        <IonIcon icon={stat.icon} color={stat.color} style={{ fontSize: 20 }} />
                        <p className="ion-padding-top" style={{ fontSize: 24, fontWeight: 700, margin: "0 0 2px" }}>
                          {stat.value}
                        </p>
                        <IonText color="medium">
                          <p style={{ fontSize: 12 }}>{stat.label}</p>
                        </IonText>
                      </IonCardContent>
                    </IonCard>
                  </IonCol>
                ))}
              </IonRow>
            </IonGrid>

            <div className="ion-margin-top ion-margin-bottom" style={{ display: "flex", justifyContent: "space-between", alignItems: "center" }}>
              <IonLabel style={{ fontWeight: 600 }}>{t('dashboard.recentSessions')}</IonLabel>
              <IonButton fill="clear" size="small" routerLink="/sessions">
                {t('dashboard.viewAll')}
              </IonButton>
            </div>

            {sessions.length === 0 ? (
              <IonCard>
                <IonCardContent className="ion-text-center ion-padding">
                  <IonIcon icon={desktopOutline} color="medium" style={{ fontSize: 32 }} />
                  <IonText color="medium">
                    <p style={{ fontSize: 14 }}>{t('dashboard.noSessions')}</p>
                  </IonText>
                </IonCardContent>
              </IonCard>
            ) : (
              <IonList>
                {sessions.slice(0, 5).map((session) => (
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
                      <p>on {session.workerId}</p>
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
          </div>
        )}
      </IonContent>
    </IonPage>
  )
}
