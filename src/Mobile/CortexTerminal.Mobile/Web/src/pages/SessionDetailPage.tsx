import { useMemo } from "react"
import { useTranslation } from "react-i18next"
import { useHistory } from "react-router-dom"
import {
  IonPage,
  IonHeader,
  IonToolbar,
  IonButton,
  IonIcon,
  IonTitle,
  IonContent,
} from "@ionic/react"
import { arrowBackOutline } from "ionicons/icons"
import type { NativeBridge } from "../bridge/types"
import { createTerminalGateway } from "../services/terminalGateway"
import { TerminalView } from "../terminal/TerminalView"

export function SessionDetailPage({
  bridge,
  sessionId,
}: {
  bridge: NativeBridge
  sessionId: string
}) {
  const { t } = useTranslation()
  const history = useHistory()
  const gateway = useMemo(() => createTerminalGateway(bridge), [bridge])

  return (
    <IonPage>
      <IonHeader>
        <IonToolbar>
          <IonButton
            slot="start"
            fill="clear"
            onClick={() => history.push("/sessions")}
          >
            <IonIcon icon={arrowBackOutline} slot="icon-only" />
          </IonButton>
          <IonTitle>{t('terminal.title')}</IonTitle>
        </IonToolbar>
      </IonHeader>
      <IonContent scrollY={false}>
        <div className="ion-padding" style={{ display: "flex", flexDirection: "column", height: "100%" }}>
          <TerminalView gateway={gateway} sessionId={sessionId} />
        </div>
      </IonContent>
    </IonPage>
  )
}
