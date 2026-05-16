import {
  IonButton,
  IonButtons,
  IonContent,
  IonHeader,
  IonIcon,
  IonItem,
  IonLabel,
  IonList,
  IonModal,
  IonRadio,
  IonRadioGroup,
  IonTitle,
  IonToolbar,
} from "@ionic/react";
import { desktopOutline } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import type { WorkerSummary } from "../../schemas/sessionSchema";

interface CreateSessionModalProps {
  isOpen: boolean;
  onClose: () => void;
  onlineWorkers: WorkerSummary[];
  selectedWorkerId: string | null;
  onSelectWorker: (workerId: string) => void;
  isCreating: boolean;
  onCreate: () => void;
}

export default function CreateSessionModal({
  isOpen,
  onClose,
  onlineWorkers,
  selectedWorkerId,
  onSelectWorker,
  isCreating,
  onCreate,
}: CreateSessionModalProps) {
  const { t } = useTranslation();

  return (
    <IonModal isOpen={isOpen} onDidDismiss={onClose}>
      <IonHeader>
        <IonToolbar>
          <IonButtons slot="start">
            <IonButton onClick={onClose}>
              {t("sessions.cancel")}
            </IonButton>
          </IonButtons>
          <IonTitle>{t("sessions.createSession")}</IonTitle>
          <IonButtons slot="end">
            <IonButton strong disabled={isCreating} onClick={() => void onCreate()}>
              {isCreating ? t("sessions.creating") : t("sessions.create")}
            </IonButton>
          </IonButtons>
        </IonToolbar>
      </IonHeader>
      <IonContent>
        <IonList>
          <IonItem lines="none" style={{ paddingTop: 12, paddingBottom: 4 }}>
            <IonLabel>
              <p>{t("sessions.selectWorker")}</p>
            </IonLabel>
          </IonItem>
          <IonRadioGroup
            value={selectedWorkerId}
            onIonChange={(e) => onSelectWorker(e.detail.value)}
          >
            {onlineWorkers.map((worker) => (
              <IonItem key={worker.id}>
                <IonRadio value={worker.id} labelPlacement="end">
                  <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
                    <IonIcon
                      icon={desktopOutline}
                      style={{
                        fontSize: 16,
                        color:
                          worker.status === "running"
                            ? "var(--ion-color-success)"
                            : "var(--ion-color-medium)",
                      }}
                    />
                    <div>
                      <div style={{ fontWeight: 500 }}>{worker.name}</div>
                      {worker.hostname && (
                        <div style={{ fontSize: 12, color: "var(--ion-color-medium)" }}>
                          {worker.hostname}
                          {worker.operatingSystem ? ` · ${worker.operatingSystem}` : ""}
                        </div>
                      )}
                    </div>
                  </div>
                </IonRadio>
              </IonItem>
            ))}
          </IonRadioGroup>
        </IonList>
      </IonContent>
    </IonModal>
  );
}
