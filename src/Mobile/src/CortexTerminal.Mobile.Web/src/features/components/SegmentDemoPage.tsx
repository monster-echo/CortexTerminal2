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

export default function SegmentDemoPage() {
  const { t } = useTranslation();
  const [selected, setSelected] = useState<string>("photos");

  const renderContent = () => {
    switch (selected) {
      case "photos":
        return t("demos.segment.photosContent");
      case "videos":
        return t("demos.segment.videosContent");
      case "audio":
        return t("demos.segment.audioContent");
      default:
        return "";
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.segment.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.segment.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonSegment
          value={selected}
          onIonChange={(e) => setSelected(e.detail.value as string)}
          style={{ margin: "0 16px 16px" }}
        >
          <IonSegmentButton value="photos">
            <IonLabel>{t("demos.segment.photos")}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="videos">
            <IonLabel>{t("demos.segment.videos")}</IonLabel>
          </IonSegmentButton>
          <IonSegmentButton value="audio">
            <IonLabel>{t("demos.segment.audio")}</IonLabel>
          </IonSegmentButton>
        </IonSegment>

        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              {renderContent()}
            </IonLabel>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
