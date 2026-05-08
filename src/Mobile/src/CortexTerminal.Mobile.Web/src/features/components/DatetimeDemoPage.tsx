import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonDatetime,
  IonListHeader,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function DatetimeDemoPage() {
  const { t } = useTranslation();
  const [dateValue, setDateValue] = useState<string | string[]>("");
  const [timeValue, setTimeValue] = useState<string | string[]>("");

  return (
    <IonPage>
      <PageHeader title={t("demos.datetime.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.datetime.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.datetime.date")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonDatetime
              presentation="date"
              onIonChange={(e) => setDateValue(e.detail.value ?? "")}
            />
          </IonItem>
          {dateValue && (
            <IonItem>
              <IonLabel color="primary">
                {t("demos.datetime.selected", { value: dateValue })}
              </IonLabel>
            </IonItem>
          )}
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.datetime.time")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonDatetime
              presentation="time"
              onIonChange={(e) => setTimeValue(e.detail.value ?? "")}
            />
          </IonItem>
          {timeValue && (
            <IonItem>
              <IonLabel color="primary">
                {t("demos.datetime.selected", { value: timeValue })}
              </IonLabel>
            </IonItem>
          )}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
