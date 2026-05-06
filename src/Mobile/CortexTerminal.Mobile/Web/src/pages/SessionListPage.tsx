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
  IonSegment,
  IonSegmentButton,
  IonList,
  IonItem,
  IonLabel,
  IonBadge,
  IonItemSliding,
  IonItemOptions,
  IonItemOption,
  IonSkeletonText,
  IonText,
} from "@ionic/react"
import { addOutline, trashOutline } from "ionicons/icons"
import type { ConsoleApi, SessionSummary } from "../services/consoleApi"

type SessionFilter = "all" | "live" | "detached" | "exited"

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

export function SessionListPage({ api }: { api: ConsoleApi }) {
  const history = useHistory()
  const [sessions, setSessions] = useState<SessionSummary[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [isCreating, setIsCreating] = useState(false)
  const [filter, setFilter] = useState<SessionFilter>("all")
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  const loadSessions = () => {
    let isActive = true
    setIsLoading(true)
    api
      .listSessions()
      .then((value) => {
        if (!isActive) return
        setSessions(value)
        setErrorMessage(null)
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(
          error instanceof Error ? error.message : "Could not load sessions.",
        )
      })
      .finally(() => {
        if (isActive) setIsLoading(false)
      })
    return () => {
      isActive = false
    }
  }

  useEffect(loadSessions, [api])

  const handleCreate = async () => {
    setIsCreating(true)
    setErrorMessage(null)
    try {
      const created = await api.createSession()
      history.push(`/sessions/${created.sessionId}`)
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Could not start session.",
      )
    } finally {
      setIsCreating(false)
    }
  }

  const handleDelete = async (sessionId: string) => {
    try {
      await api.deleteSession(sessionId)
      setSessions((prev) => prev.filter((s) => s.sessionId !== sessionId))
    } catch (error) {
      setErrorMessage(
        error instanceof Error ? error.message : "Could not delete session.",
      )
    }
  }

  const filtered = sessions.filter((s) => {
    if (filter === "all") return true
    return s.status === filter
  })

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonTitle>Sessions</IonTitle>
          <IonButton
            slot="end"
            fill="solid"
            size="small"
            onClick={() => void handleCreate()}
            disabled={isCreating}
          >
            <IonIcon icon={addOutline} slot="start" />
            New
          </IonButton>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        <IonSegment
          value={filter}
          onIonChange={(e) => setFilter(e.detail.value as SessionFilter)}
          style={{ margin: "8px 16px" }}
        >
          <IonSegmentButton value="all">
            <IonLabel>All</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="live">
            <IonLabel>Live</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="detached">
            <IonLabel>Detached</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="exited">
            <IonLabel>Exited</IonLabel>
          </IonSegmentButton>
        </IonSegment>

        {errorMessage && (
          <div style={{ padding: "0 16px" }}>
            <IonText color="danger">
              <p style={{ fontSize: 13 }}>{errorMessage}</p>
            </IonText>
          </div>
        )}

        {isLoading ? (
          <div style={{ padding: 16 }}>
            {[1, 2, 3].map((i) => (
              <IonItem key={i}>
                <IonSkeletonText animated style={{ height: 20 }} />
              </IonItem>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              padding: "48px 16px",
            }}
          >
            <IonText color="medium">
              <p>No {filter === "all" ? "" : filter} sessions</p>
            </IonText>
          </div>
        ) : (
          <IonList>
            {filtered.map((session) => (
              <IonItemSliding key={session.sessionId}>
                <IonItem
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
                        fontWeight: 600,
                      }}
                    >
                      {session.sessionId}
                    </h3>
                    <p>
                      {session.workerId} &middot;{" "}
                      {new Date(session.lastActivityAt).toLocaleTimeString([], {
                        hour: "2-digit",
                        minute: "2-digit",
                      })}
                    </p>
                  </IonLabel>
                  <IonBadge
                    slot="end"
                    color={statusBadgeColor[session.status] ?? "medium"}
                  >
                    {session.status}
                  </IonBadge>
                </IonItem>
                <IonItemOptions side="end">
                  <IonItemOption
                    color="danger"
                    onClick={() => void handleDelete(session.sessionId)}
                  >
                    <IonIcon icon={trashOutline} slot="icon-only" />
                  </IonItemOption>
                </IonItemOptions>
              </IonItemSliding>
            ))}
          </IonList>
        )}
      </IonContent>
    </IonPage>
  )
}
