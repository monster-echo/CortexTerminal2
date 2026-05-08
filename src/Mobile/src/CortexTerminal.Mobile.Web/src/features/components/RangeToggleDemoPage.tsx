import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonRange,
  IonToggle,
  IonListHeader,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function RangeToggleDemoPage() {
  const { t } = useTranslation();
  const [brightness, setBrightness] = useState(50);
  const [volume, setVolume] = useState(70);
  const [toggles, setToggles] = useState<Record<string, boolean>>({
    darkMode: false,
    notifications: true,
    wifi: true,
    bluetooth: false,
  });

  const handleToggle = (key: string, checked: boolean) => {
    setToggles((prev) => ({ ...prev, [key]: checked }));
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.rangeToggle.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.rangeToggle.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.rangeToggle.brightness")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonRange
              min={0}
              max={100}
              step={1}
              value={brightness}
              pin
              onIonInput={(e) => setBrightness(e.detail.value as number)}
            >
              <IonLabel slot="start">0</IonLabel>
              <IonLabel slot="end">100</IonLabel>
            </IonRange>
          </IonItem>
          <IonItem>
            <IonLabel color="primary">
              {t("demos.rangeToggle.value", { value: brightness })}
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.rangeToggle.volume")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonRange
              min={0}
              max={100}
              step={10}
              value={volume}
              pin
              onIonInput={(e) => setVolume(e.detail.value as number)}
            >
              <IonLabel slot="start">0</IonLabel>
              <IonLabel slot="end">100</IonLabel>
            </IonRange>
          </IonItem>
          <IonItem>
            <IonLabel color="primary">
              {t("demos.rangeToggle.value", { value: volume })}
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>Toggle</IonLabel>
          </IonListHeader>
          {(["darkMode", "notifications", "wifi", "bluetooth"] as const).map((key) => (
            <IonItem key={key}>
              <IonToggle
                checked={toggles[key]}
                onIonChange={(e) => handleToggle(key, e.detail.checked)}
              >
                {t(`demos.rangeToggle.${key}`)}
              </IonToggle>
              <IonLabel slot="end" color={toggles[key] ? "primary" : "medium"} style={{ fontSize: 12 }}>
                {toggles[key] ? t("demos.rangeToggle.enabled") : t("demos.rangeToggle.disabled")}
              </IonLabel>
            </IonItem>
          ))}
        </IonList>
      </IonContent>
    </IonPage>
  );
}
