import { useEffect, useState } from "react"
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

export function DashboardPage({ api }: { api: ConsoleApi }) {
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
    {
      label: "Active",
      value: liveCount,
      icon: pulseOutline,
      color: "#10b981",
    },
    {
      label: "Detached",
      value: detachedCount,
      icon: desktopOutline,
      color: "#f59e0b",
    },
    {
      label: "Workers",
      value: workerCount,
      icon: serverOutline,
      color: "#3b82f6",
    },
    {
      label: "Total",
      value: sessions.length,
      icon: timeOutline,
      color: "#8b5cf6",
    },
  ]

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonTitle>Dashboard</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        {isLoading ? (
          <div style={{ padding: 16 }}>
            <IonGrid>
              <IonRow>
                {[1, 2, 3, 4].map((i) => (
                  <IonCol size="6" key={i}>
                    <IonCard>
                      <IonCardContent>
                        <IonSkeletonText
                          animated
                          style={{ height: 80 }}
                        />
                      </IonCardContent>
                    </IonCard>
                  </IonCol>
                ))}
              </IonRow>
            </IonGrid>
          </div>
        ) : (
          <div style={{ padding: 16 }}>
            <IonGrid>
              <IonRow>
                {stats.map((stat) => (
                  <IonCol size="6" key={stat.label}>
                    <IonCard>
                      <IonCardContent>
                        <IonIcon
                          icon={stat.icon}
                          style={{ fontSize: 20, color: stat.color }}
                        />
                        <p
                          style={{
                            fontSize: 24,
                            fontWeight: 700,
                            margin: "8px 0 2px",
                          }}
                        >
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

            <div
              style={{
                display: "flex",
                justifyContent: "space-between",
                alignItems: "center",
                marginTop: 8,
                marginBottom: 8,
              }}
            >
              <p style={{ fontSize: 14, fontWeight: 600, margin: 0 }}>
                Recent Sessions
              </p>
              <IonButton
                fill="clear"
                size="small"
                routerLink="/sessions"
              >
                View all
              </IonButton>
            </div>

            {sessions.length === 0 ? (
              <IonCard>
                <IonCardContent
                  style={{ textAlign: "center", padding: 32 }}
                >
                  <IonIcon
                    icon={desktopOutline}
                    style={{
                      fontSize: 32,
                      color: "var(--ion-color-medium)",
                    }}
                  />
                  <p
                    style={{
                      color: "var(--ion-color-medium)",
                      fontSize: 14,
                    }}
                  >
                    No sessions yet
                  </p>
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
