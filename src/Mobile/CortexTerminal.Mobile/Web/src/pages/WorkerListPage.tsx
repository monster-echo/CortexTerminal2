import { useEffect, useState } from "react"
import { useTranslation } from "react-i18next"
import { useHistory } from "react-router-dom"
import {
  IonPage,
  IonHeader,
  IonToolbar,
  IonTitle,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonIcon,
  IonSkeletonText,
  IonText,
} from "@ionic/react"
import { chevronForwardOutline } from "ionicons/icons"
import type { ConsoleApi, WorkerSummary } from "../services/consoleApi"
import { StatusDot } from "../components/StatusDot"

export function WorkerListPage({ api }: { api: ConsoleApi }) {
  const { t } = useTranslation()
  const history = useHistory()
  const [workers, setWorkers] = useState<WorkerSummary[]>([])
  const [isLoading, setIsLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState<string | null>(null)

  useEffect(() => {
    let isActive = true
    api
      .listWorkers()
      .then((value) => {
        if (!isActive) return
        setWorkers(value)
        setErrorMessage(null)
      })
      .catch((error: unknown) => {
        if (!isActive) return
        setErrorMessage(
          error instanceof Error ? error.message : t('workers.loadError'),
        )
      })
      .finally(() => {
        if (isActive) setIsLoading(false)
      })
    return () => {
      isActive = false
    }
  }, [api])

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonTitle>{t('workers.title')}</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
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
        ) : workers.length === 0 ? (
          <div className="empty-state">
            <IonText color="medium">
              <p>{t('workers.noWorkers')}</p>
            </IonText>
          </div>
        ) : (
          <IonList>
            {workers.map((worker) => (
              <IonItem
                key={worker.workerId}
                button
                onClick={() => history.push(`/workers/${worker.workerId}`)}
              >
                <StatusDot status={worker.isOnline ? "online" : "offline"} />
                <IonLabel>
                  <h3>{worker.name}</h3>
                  <p>
                    {worker.sessionCount} sessions &middot;{" "}
                    {new Date(worker.lastSeenAt).toLocaleTimeString([], {
                      hour: "2-digit",
                      minute: "2-digit",
                    })}
                  </p>
                </IonLabel>
                <IonText
                  slot="end"
                  color={worker.isOnline ? "success" : "medium"}
                >
                  <span style={{ fontSize: 12, fontWeight: 500 }}>
                    {worker.isOnline ? t('workers.online') : t('workers.offline')}
                  </span>
                </IonText>
                <IonIcon
                  icon={chevronForwardOutline}
                  slot="end"
                  color="medium"
                  style={{ marginLeft: 8, fontSize: 18 }}
                />
              </IonItem>
            ))}
          </IonList>
        )}
      </IonContent>
    </IonPage>
  )
}
