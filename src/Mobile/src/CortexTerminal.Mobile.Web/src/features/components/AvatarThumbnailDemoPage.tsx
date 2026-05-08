import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonAvatar,
  IonThumbnail,
  IonListHeader,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function AvatarThumbnailDemoPage() {
  const { t } = useTranslation();

  return (
    <IonPage>
      <PageHeader title={t("demos.avatarThumbnail.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.avatarThumbnail.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.avatarThumbnail.avatarSection")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <div style={{ display: "flex", gap: 16, alignItems: "center", padding: "8px 0" }}>
              <IonAvatar style={{ width: "32px", height: "32px" }}>
                <img src="https://ionicframework.com/docs/img/demos/avatar.svg" alt="" />
              </IonAvatar>
              <IonAvatar style={{ width: "48px", height: "48px" }}>
                <img src="https://ionicframework.com/docs/img/demos/avatar.svg" alt="" />
              </IonAvatar>
              <IonAvatar style={{ width: "64px", height: "64px" }}>
                <img src="https://ionicframework.com/docs/img/demos/avatar.svg" alt="" />
              </IonAvatar>
            </div>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.avatarThumbnail.thumbnailSection")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <div style={{ display: "flex", gap: 16, alignItems: "center", padding: "8px 0" }}>
              <IonThumbnail style={{ width: "40px", height: "40px" }}>
                <img src="https://ionicframework.com/docs/img/demos/thumbnail.svg" alt="" />
              </IonThumbnail>
              <IonThumbnail style={{ width: "60px", height: "60px" }}>
                <img src="https://ionicframework.com/docs/img/demos/thumbnail.svg" alt="" />
              </IonThumbnail>
              <IonThumbnail style={{ width: "80px", height: "80px" }}>
                <img src="https://ionicframework.com/docs/img/demos/thumbnail.svg" alt="" />
              </IonThumbnail>
            </div>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.avatarThumbnail.inList")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonAvatar slot="start">
              <img src="https://ionicframework.com/docs/img/demos/avatar.svg" alt="" />
            </IonAvatar>
            <IonLabel>
              <h2>{t("demos.avatarThumbnail.userName")}</h2>
              <p>{t("demos.avatarThumbnail.userDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonThumbnail slot="start">
              <img src="https://ionicframework.com/docs/img/demos/thumbnail.svg" alt="" />
            </IonThumbnail>
            <IonLabel>
              <h2>{t("demos.avatarThumbnail.userName")}</h2>
              <p>{t("demos.avatarThumbnail.userDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
