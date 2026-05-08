import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonButton,
  IonList,
  IonItem,
  IonLabel,
  IonPopover,
  IonListHeader,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function PopoverDemoPage() {
  const { t } = useTranslation();
  const [popoverEvent, setPopoverEvent] = useState<Event | undefined>();
  const [selectedItem, setSelectedItem] = useState("");

  const handleSelect = (item: string) => {
    setSelectedItem(item);
    setPopoverEvent(undefined);
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.popover.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.popover.title")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.popover.description")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonButton
              expand="block"
              onClick={(e) => {
                setPopoverEvent(e.nativeEvent);
              }}
            >
              {t("demos.popover.open")}
            </IonButton>
          </IonItem>
          {selectedItem && (
            <IonItem>
              <IonLabel color="primary">
                {t("demos.popover.selected")}: {selectedItem}
              </IonLabel>
            </IonItem>
          )}
        </IonList>

        <IonPopover
          event={popoverEvent}
          isOpen={popoverEvent !== undefined}
          onDidDismiss={() => setPopoverEvent(undefined)}
        >
          <IonContent>
            <IonList>
              <IonItem
                button
                onClick={() => handleSelect(t("demos.popover.copy"))}
              >
                <IonLabel>{t("demos.popover.copy")}</IonLabel>
              </IonItem>
              <IonItem
                button
                onClick={() => handleSelect(t("demos.popover.paste"))}
              >
                <IonLabel>{t("demos.popover.paste")}</IonLabel>
              </IonItem>
              <IonItem
                button
                onClick={() => handleSelect(t("demos.popover.delete"))}
              >
                <IonLabel color="danger">{t("demos.popover.delete")}</IonLabel>
              </IonItem>
            </IonList>
          </IonContent>
        </IonPopover>
      </IonContent>
    </IonPage>
  );
}
