import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonRadioGroup,
  IonRadio,
  IonCheckbox,
  IonListHeader,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

const radioOptions = ["option1", "option2", "option3"] as const;
const checkboxOptions = ["darkMode", "notifications", "wifi"] as const;

export default function RadioCheckboxDemoPage() {
  const { t } = useTranslation();
  const [selectedRadio, setSelectedRadio] = useState("option1");
  const [checkedItems, setCheckedItems] = useState<Record<string, boolean>>({
    darkMode: false,
    notifications: true,
    wifi: true,
  });

  const handleCheckboxChange = (key: string, checked: boolean) => {
    setCheckedItems((prev) => ({ ...prev, [key]: checked }));
  };

  const checkedValues = Object.entries(checkedItems)
    .filter(([, v]) => v)
    .map(([k]) => t(`demos.rangeToggle.${k}`))
    .join(", ");

  return (
    <IonPage>
      <PageHeader title={t("demos.radioCheckbox.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.radioCheckbox.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.radioCheckbox.radioSection")}</IonLabel>
          </IonListHeader>
          <IonRadioGroup
            value={selectedRadio}
            onIonChange={(e) => setSelectedRadio(e.detail.value)}
          >
            {radioOptions.map((opt) => (
              <IonItem key={opt}>
                <IonRadio value={opt} labelPlacement="end">
                  {t(`demos.radioCheckbox.${opt}`)}
                </IonRadio>
              </IonItem>
            ))}
          </IonRadioGroup>
          <IonItem>
            <IonLabel color="primary">
              {t("demos.radioCheckbox.selected", { value: t(`demos.radioCheckbox.${selectedRadio}`) })}
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.radioCheckbox.checkboxSection")}</IonLabel>
          </IonListHeader>
          {checkboxOptions.map((opt) => (
            <IonItem key={opt}>
              <IonCheckbox
                checked={checkedItems[opt]}
                onIonChange={(e) => handleCheckboxChange(opt, e.detail.checked)}
                labelPlacement="end"
              >
                {t(`demos.rangeToggle.${opt}`)}
              </IonCheckbox>
            </IonItem>
          ))}
          <IonItem>
            <IonLabel color="primary">
              {t("demos.radioCheckbox.checked", { values: checkedValues || "—" })}
            </IonLabel>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
