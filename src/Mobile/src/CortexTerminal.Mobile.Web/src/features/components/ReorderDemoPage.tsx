import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonReorderGroup,
  IonReorder,
  IonButton,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function ReorderDemoPage() {
  const { t } = useTranslation();
  const [items, setItems] = useState<string[]>(
    Array.from({ length: 8 }, (_, i) => t("demos.reorder.item", { index: i + 1 }))
  );
  const [reorderEnabled, setReorderEnabled] = useState(false);

  const handleReorder = (event: CustomEvent) => {
    const fromIndex = event.detail.from as number;
    const toIndex = event.detail.to as number;
    const reordered = [...items];
    const [moved] = reordered.splice(fromIndex, 1);
    reordered.splice(toIndex, 0, moved);
    setItems(reordered);
    event.detail.complete(reordered);
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.reorder.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.reorder.description")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonButton
              expand="block"
              onClick={() => setReorderEnabled((prev) => !prev)}
            >
              {reorderEnabled
                ? t("demos.reorder.disable")
                : t("demos.reorder.enable")}
            </IonButton>
          </IonItem>
        </IonList>

        <IonList>
          <IonReorderGroup disabled={!reorderEnabled} onIonItemReorder={handleReorder}>
            {items.map((item, index) => (
              <IonItem key={index}>
                <IonLabel>{item}</IonLabel>
                <IonReorder slot="end" />
              </IonItem>
            ))}
          </IonReorderGroup>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
