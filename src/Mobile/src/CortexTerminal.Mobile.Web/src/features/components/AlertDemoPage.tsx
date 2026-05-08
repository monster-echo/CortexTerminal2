import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonButton,
  IonList,
  IonItem,
  IonLabel,
  IonListHeader,
  useIonAlert,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function AlertDemoPage() {
  const { t } = useTranslation();
  const [result, setResult] = useState("");
  const [presentAlert] = useIonAlert();

  const showBasicAlert = () => {
    presentAlert({
      header: t("demos.alert.basicHeader"),
      message: t("demos.alert.basicMessage"),
      buttons: ["OK"],
    });
  };

  const showConfirmAlert = () => {
    presentAlert({
      header: t("demos.alert.confirmHeader"),
      message: t("demos.alert.confirmMessage"),
      buttons: [
        {
          text: t("demos.alert.cancel"),
          role: "cancel",
        },
        {
          text: t("demos.alert.ok"),
          handler: () => {
            setResult(t("demos.alert.confirmed"));
          },
        },
      ],
    });
  };

  const showPromptAlert = () => {
    presentAlert({
      header: t("demos.alert.promptHeader"),
      message: t("demos.alert.promptMessage"),
      inputs: [
        {
          placeholder: t("demos.alert.promptPlaceholder"),
        },
      ],
      buttons: [
        {
          text: t("demos.alert.cancel"),
          role: "cancel",
        },
        {
          text: t("demos.alert.ok"),
          handler: (data) => {
            const input = data?.[0] ?? "";
            setResult(`${t("demos.alert.promptResult")}: ${input}`);
          },
        },
      ],
    });
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.alert.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.alert.title")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.alert.description")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={showBasicAlert}>
              {t("demos.alert.basic")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={showConfirmAlert}>
              {t("demos.alert.confirm")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={showPromptAlert}>
              {t("demos.alert.prompt")}
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
