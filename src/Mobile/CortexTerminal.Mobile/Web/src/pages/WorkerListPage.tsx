import { useEffect, useState } from "react"
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

export function WorkerListPage({ api }: { api: ConsoleApi }) {
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
          error instanceof Error ? error.message : "Could not load workers.",
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
          <IonTitle>Workers</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent>
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
        ) : workers.length === 0 ? (
          <div
            style={{
              display: "flex",
              flexDirection: "column",
              alignItems: "center",
              padding: "48px 16px",
            }}
          >
            <IonText color="medium">
              <p>No workers connected</p>
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
                <span
                  style={{
                    width: 10,
                    height: 10,
                    borderRadius: "50%",
                    backgroundColor: worker.isOnline ? "#10b981" : "#71717a",
                    marginRight: 12,
                    flexShrink: 0,
                  }}
                />
                <IonLabel>
                  <h3 style={{ fontWeight: 600 }}>{worker.name}</h3>
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
                    {worker.isOnline ? "Online" : "Offline"}
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
