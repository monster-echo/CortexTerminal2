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
import { StatusDot } from "../components/StatusDot"

type SessionFilter = "all" | "live" | "detached" | "exited"

const statusBadgeColor: Record<string, string> = {
  live: "success",
  detached: "warning",
  exited: "danger",
  expired: "medium",
}

export function SessionListPage({ api }: { api: ConsoleApi }) {
  const { t } = useTranslation()
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
          error instanceof Error ? error.message : t('sessions.loadError'),
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
        error instanceof Error ? error.message : t('sessions.createError'),
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
        error instanceof Error ? error.message : t('sessions.deleteError'),
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
          <IonTitle>{t('sessions.title')}</IonTitle>
          <IonButton
            slot="end"
            fill="solid"
            size="small"
            onClick={() => void handleCreate()}
            disabled={isCreating}
          >
            <IonIcon icon={addOutline} slot="start" />
            {t('sessions.new')}
          </IonButton>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        <IonSegment
          value={filter}
          onIonChange={(e) => setFilter(e.detail.value as SessionFilter)}
          className="ion-padding-horizontal ion-margin-top"
        >
          <IonSegmentButton value="all">
            <IonLabel>{t('sessions.filterAll')}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="live">
            <IonLabel>{t('sessions.filterLive')}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="detached">
            <IonLabel>{t('sessions.filterDetached')}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="exited">
            <IonLabel>{t('sessions.filterExited')}</IonLabel>
          </IonSegmentButton>
        </IonSegment>

        {errorMessage && (
          <div className="ion-padding-horizontal">
            <IonText color="danger">
              <p style={{ fontSize: 13 }}>{errorMessage}</p>
            </IonText>
          </div>
        )}

        {isLoading ? (
          <div className="ion-padding">
            {[1, 2, 3].map((i) => (
              <IonItem key={i}>
                <IonSkeletonText animated style={{ height: 20 }} />
              </IonItem>
            ))}
          </div>
        ) : filtered.length === 0 ? (
          <div className="empty-state">
            <IonText color="medium">
              <p>{t('sessions.noSessions', { filter: filter === 'all' ? '' : t('sessions.filter' + filter.charAt(0).toUpperCase() + filter.slice(1)) + ' ' })}</p>
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
                  <StatusDot status={session.status} />
                  <IonLabel>
                    <h3 className="mono">{session.sessionId}</h3>
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
