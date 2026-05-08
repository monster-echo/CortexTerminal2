import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonRefresher,
  IonRefresherContent,
  useIonToast,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function RefresherDemoPage() {
  const { t } = useTranslation();
  const [presentToast] = useIonToast();
  const [items, setItems] = useState<string[]>(
    Array.from({ length: 10 }, (_, i) => t("demos.refresher.item", { index: i + 1 }))
  );

  const handleRefresh = (event: CustomEvent) => {
    setTimeout(() => {
      setItems((prev) => [
        t("demos.refresher.item", { index: prev.length + 1 }),
        ...prev,
      ]);
      event.detail.complete();
      presentToast({
        message: t("demos.refresher.refreshed"),
        duration: 1500,
        position: "bottom",
      });
    }, 1500);
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.refresher.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonRefresher slot="fixed" onIonRefresh={handleRefresh}>
          <IonRefresherContent />
        </IonRefresher>

        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.refresher.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList>
          {items.map((item, index) => (
            <IonItem key={index}>
              <IonLabel>{item}</IonLabel>
            </IonItem>
          ))}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
