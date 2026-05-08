import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonSegment,
  IonSegmentButton,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function TabsDemoPage() {
  const { t } = useTranslation();
  const [activeTab, setActiveTab] = useState<string>("tab1");

  const renderContent = () => {
    switch (activeTab) {
      case "tab1":
        return (
          <IonList inset>
            <IonItem>
              <IonLabel className="ion-text-wrap">
                {t("demos.tabs.tab1Content")}
              </IonLabel>
            </IonItem>
          </IonList>
        );
      case "tab2":
        return (
          <IonList inset>
            <IonItem>
              <IonLabel className="ion-text-wrap">
                {t("demos.tabs.tab2Content")}
              </IonLabel>
            </IonItem>
          </IonList>
        );
      case "tab3":
        return (
          <IonList inset>
            <IonItem>
              <IonLabel className="ion-text-wrap">
                {t("demos.tabs.tab3Content")}
              </IonLabel>
            </IonItem>
          </IonList>
        );
      default:
        return null;
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.tabs.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.tabs.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonSegment
          value={activeTab}
          onIonChange={(e) => setActiveTab(e.detail.value as string)}
          style={{ margin: "0 16px 16px" }}
        >
          <IonSegmentButton value="tab1">
            <IonLabel>{t("demos.tabs.tab1")}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="tab2">
            <IonLabel>{t("demos.tabs.tab2")}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="tab3">
            <IonLabel>{t("demos.tabs.tab3")}</IonLabel>
          </IonSegmentButton>
        </IonSegment>

        {renderContent()}
      </IonContent>
    </IonPage>
  );
}
