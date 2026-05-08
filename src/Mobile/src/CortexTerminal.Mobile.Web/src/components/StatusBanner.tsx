import { IonIcon, IonText } from "@ionic/react";
import {
  alertCircleOutline,
  checkmarkCircleOutline,
  cloudOfflineOutline,
} from "ionicons/icons";

export interface StatusBannerProps {
  kind: "success" | "warning" | "offline";
  title: string;
  description: string;
}

const iconByKind = {
  success: checkmarkCircleOutline,
  warning: alertCircleOutline,
  offline: cloudOfflineOutline,
};

export default function StatusBanner({
  kind,
  title,
  description,
}: StatusBannerProps) {
  return (
    <div className={`status-banner status-${kind}`}>
      <IonIcon icon={iconByKind[kind]} className="status-icon" />
      <div>
        <strong>{title}</strong>
        <IonText color="medium">
          <p>{description}</p>
        </IonText>
      </div>
    </div>
  );
}
