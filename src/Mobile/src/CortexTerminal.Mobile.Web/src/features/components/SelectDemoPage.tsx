import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonSelect,
  IonSelectOption,
  IonListHeader,
  IonSegment,
  IonSegmentButton,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

const fruits = ["apple", "banana", "cherry", "orange", "grape"] as const;

export default function SelectDemoPage() {
  const { t } = useTranslation();
  const [singleValue, setSingleValue] = useState("");
  const [multiValue, setMultiValue] = useState<string[]>([]);
  const [interfaceType, setInterfaceType] = useState<string>("popover");
  const [interfaceValue, setInterfaceValue] = useState("");

  return (
    <IonPage>
      <PageHeader title={t("demos.select.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.select.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.select.single")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonSelect
              label={t("demos.select.singlePlaceholder")}
              labelPlacement="stacked"
              value={singleValue}
              onIonChange={(e) => setSingleValue(e.detail.value)}
              interface="popover"
            >
              {fruits.map((f) => (
                <IonSelectOption key={f} value={f}>
                  {t(`demos.select.${f}`)}
                </IonSelectOption>
              ))}
            </IonSelect>
          </IonItem>
          {singleValue && (
            <IonItem>
              <IonLabel color="primary">
                {t("demos.select.selected")}{t(`demos.select.${singleValue}`)}
              </IonLabel>
            </IonItem>
          )}
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.select.multiple")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonSelect
              label={t("demos.select.multiplePlaceholder")}
              labelPlacement="stacked"
              value={multiValue}
              onIonChange={(e) => setMultiValue(e.detail.value)}
              multiple
              interface="alert"
            >
              {fruits.map((f) => (
                <IonSelectOption key={f} value={f}>
                  {t(`demos.select.${f}`)}
                </IonSelectOption>
              ))}
            </IonSelect>
          </IonItem>
          {multiValue.length > 0 && (
            <IonItem>
              <IonLabel color="primary">
                {t("demos.select.selected")}{multiValue.map((v) => t(`demos.select.${v}`)).join(", ")}
              </IonLabel>
            </IonItem>
          )}
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.select.interface")}</IonLabel>
          </IonListHeader>
          <IonSegment
            value={interfaceType}
            onIonChange={(e) => setInterfaceType(e.detail.value as string)}
            style={{ margin: "8px 16px" }}
          >
            <IonSegmentButton value="popover">
              <IonLabel>{t("demos.select.popover")}</IonLabel>
            </IonSegmentButton>
            <IonSegmentButton value="action-sheet">
              <IonLabel>{t("demos.select.actionSheet")}</IonLabel>
            </IonSegmentButton>
            <IonSegmentButton value="alert">
              <IonLabel>{t("demos.select.alert")}</IonLabel>
            </IonSegmentButton>
          </IonSegment>
          <IonItem>
            <IonSelect
              label={t("demos.select.singlePlaceholder")}
              labelPlacement="stacked"
              value={interfaceValue}
              onIonChange={(e) => setInterfaceValue(e.detail.value)}
              interface={interfaceType as "popover" | "action-sheet" | "alert"}
            >
              {fruits.map((f) => (
                <IonSelectOption key={f} value={f}>
                  {t(`demos.select.${f}`)}
                </IonSelectOption>
              ))}
            </IonSelect>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
