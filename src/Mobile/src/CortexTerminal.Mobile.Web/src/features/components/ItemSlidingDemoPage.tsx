import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonItemSliding,
  IonItemOptions,
  IonItemOption,
  useIonToast,
} from "@ionic/react";
import { archiveOutline, eyeOutline, trashOutline } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function ItemSlidingDemoPage() {
  const { t } = useTranslation();
  const [presentToast] = useIonToast();

  const showMessage = (message: string) => {
    presentToast({
      message,
      duration: 1500,
      position: "bottom",
    });
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.itemSliding.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.itemSliding.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList>
          {Array.from({ length: 6 }, (_, i) => i + 1).map((n) => (
            <IonItemSliding key={n}>
              <IonItemOptions side="start">
                <IonItemOption
                  color="primary"
                  onClick={() => showMessage(t("demos.itemSliding.archived", { item: n }))}
                >
                  <IonLabel>{t("demos.itemSliding.archive")}</IonLabel>
                </IonItemOption>
                <IonItemOption
                  onClick={() => showMessage(t("demos.itemSliding.markedRead", { item: n }))}
                >
                  <IonLabel>{t("demos.itemSliding.markRead")}</IonLabel>
                </IonItemOption>
              </IonItemOptions>

              <IonItem>
                <IonLabel>{t("demos.itemSliding.item", { index: n })}</IonLabel>
              </IonItem>

              <IonItemOptions side="end">
                <IonItemOption
                  color="danger"
                  onClick={() => showMessage(t("demos.itemSliding.deleted", { item: n }))}
                >
                  <IonLabel>{t("demos.itemSliding.delete")}</IonLabel>
                </IonItemOption>
              </IonItemOptions>
            </IonItemSliding>
          ))}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
