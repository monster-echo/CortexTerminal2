import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonAccordionGroup,
  IonAccordion,
  IonSegment,
  IonSegmentButton,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function AccordionDemoPage() {
  const { t } = useTranslation();
  const [mode, setMode] = useState<string>("single");

  return (
    <IonPage>
      <PageHeader title={t("demos.accordion.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.accordion.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonSegment
          value={mode}
          onIonChange={(e) => setMode(e.detail.value as string)}
          style={{ margin: "0 16px" }}
        >
          <IonSegmentButton value="single">
            <IonLabel>{t("demos.accordion.single")}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="toggle">
            <IonLabel>{t("demos.accordion.toggle")}</IonLabel>
          </IonSegmentButton>
        </IonSegment>

        <IonList style={{ marginTop: 16 }}>
          <IonAccordionGroup
            expand={mode === "toggle" ? "inset" : undefined}
            multiple={mode === "toggle"}
          >
            <IonAccordion value="item1">
              <IonItem slot="header">
                <IonLabel>{t("demos.accordion.item1Title")}</IonLabel>
              </IonItem>
              <div className="ion-padding" slot="content">
                {t("demos.accordion.item1Content")}
              </div>
            </IonAccordion>

            <IonAccordion value="item2">
              <IonItem slot="header">
                <IonLabel>{t("demos.accordion.item2Title")}</IonLabel>
              </IonItem>
              <div className="ion-padding" slot="content">
                {t("demos.accordion.item2Content")}
              </div>
            </IonAccordion>

            <IonAccordion value="item3">
              <IonItem slot="header">
                <IonLabel>{t("demos.accordion.item3Title")}</IonLabel>
              </IonItem>
              <div className="ion-padding" slot="content">
                {t("demos.accordion.item3Content")}
              </div>
            </IonAccordion>
          </IonAccordionGroup>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
