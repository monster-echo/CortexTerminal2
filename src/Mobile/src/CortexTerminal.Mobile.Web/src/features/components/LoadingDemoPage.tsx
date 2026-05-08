import {
  IonPage,
  IonContent,
  IonButton,
  IonList,
  IonItem,
  IonLabel,
  IonListHeader,
  useIonLoading,
  useIonToast,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function LoadingDemoPage() {
  const { t } = useTranslation();
  const [presentLoading, dismissLoading] = useIonLoading();
  const [presentToast] = useIonToast();

  const handleShowLoading = () => {
    presentLoading({
      message: t("demos.loading.message"),
    });
    setTimeout(() => {
      dismissLoading();
      presentToast({
        message: t("demos.loading.complete"),
        duration: 2000,
        position: "bottom",
      });
    }, 2000);
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.loading.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.loading.title")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.loading.description")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={handleShowLoading}>
              {t("demos.loading.show")}
            </IonButton>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
