import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonFab,
  IonFabButton,
  IonFabList,
  IonIcon,
} from "@ionic/react";
import { share, logoFacebook, logoTwitter, logoLinkedin, camera, document } from "ionicons/icons";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function FabDemoPage() {
  const { t } = useTranslation();

  return (
    <IonPage>
      <PageHeader title={t("demos.fab.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.fab.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonFab horizontal="end" vertical="bottom" slot="fixed">
          <IonFabButton>
            <IonIcon icon={share} />
          </IonFabButton>
          <IonFabList side="top">
            <IonFabButton>
              <IonIcon icon={logoFacebook} />
            </IonFabButton>
            <IonFabButton>
              <IonIcon icon={logoTwitter} />
            </IonFabButton>
            <IonFabButton>
              <IonIcon icon={logoLinkedin} />
            </IonFabButton>
          </IonFabList>
          <IonFabList side="start">
            <IonFabButton>
              <IonIcon icon={camera} />
            </IonFabButton>
            <IonFabButton>
              <IonIcon icon={document} />
            </IonFabButton>
          </IonFabList>
        </IonFab>
      </IonContent>
    </IonPage>
  );
}
