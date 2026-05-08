import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonButton,
  IonList,
  IonItem,
  IonLabel,
  IonListHeader,
  useIonActionSheet,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function ActionSheetDemoPage() {
  const { t } = useTranslation();
  const [result, setResult] = useState("");
  const [presentActionSheet] = useIonActionSheet();

  const handlePresent = () => {
    presentActionSheet({
      header: t("demos.actionSheet.header"),
      buttons: [
        {
          text: t("demos.actionSheet.delete"),
          role: "destructive",
          handler: () => {
            setResult(t("demos.actionSheet.deleteSelected"));
          },
        },
        {
          text: t("demos.actionSheet.share"),
          handler: () => {
            setResult(t("demos.actionSheet.shareSelected"));
          },
        },
        {
          text: t("demos.actionSheet.cancel"),
          role: "cancel",
        },
      ],
    });
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.actionSheet.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.actionSheet.title")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.actionSheet.description")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={handlePresent}>
              {t("demos.actionSheet.open")}
            </IonButton>
          </IonItem>
          {result && (
            <IonItem>
              <IonLabel color="primary">{result}</IonLabel>
            </IonItem>
          )}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
