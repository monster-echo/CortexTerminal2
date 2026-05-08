import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonInfiniteScroll,
  IonInfiniteScrollContent,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function InfiniteScrollDemoPage() {
  const { t } = useTranslation();
  const [items, setItems] = useState<string[]>(
    Array.from({ length: 20 }, (_, i) => t("demos.infiniteScroll.item", { index: i + 1 }))
  );
  const [disabled, setDisabled] = useState(false);

  const handleInfinite = (event: CustomEvent) => {
    setTimeout(() => {
      const currentLength = items.length;
      const newItems = Array.from(
        { length: 20 },
        (_, i) => t("demos.infiniteScroll.item", { index: currentLength + i + 1 })
      );
      const updated = [...items, ...newItems];

      if (updated.length >= 100) {
        setDisabled(true);
      }
      setItems(updated);
      (event.target as HTMLIonInfiniteScrollElement).complete();
    }, 500);
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.infiniteScroll.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.infiniteScroll.description")}</p>
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

        <IonInfiniteScroll onIonInfinite={handleInfinite} threshold="100px" disabled={disabled}>
          <IonInfiniteScrollContent
            loadingText={disabled ? t("demos.infiniteScroll.allLoaded") : undefined}
          />
        </IonInfiniteScroll>
      </IonContent>
    </IonPage>
  );
}
