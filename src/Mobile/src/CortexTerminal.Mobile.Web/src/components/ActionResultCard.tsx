import {
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonNote,
} from "@ionic/react";
import { useTranslation } from "react-i18next";

export interface ActionResultCardProps {
  title: string;
  detail: string;
  note?: string;
}

export default function ActionResultCard({
  title,
  detail,
  note,
}: ActionResultCardProps) {
  const { t } = useTranslation();

  return (
    <IonCard>
      <IonCardHeader>
        <IonCardTitle>{title}</IonCardTitle>
        <IonCardSubtitle>{t("components.actionResultTitle")}</IonCardSubtitle>
      </IonCardHeader>
      <IonCardContent>
        <pre>{detail}</pre>
        {note ? (
          <p>
            <IonNote color="medium">{note}</IonNote>
          </p>
        ) : null}
      </IonCardContent>
    </IonCard>
  );
}
