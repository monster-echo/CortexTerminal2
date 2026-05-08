import {
  IonPage,
  IonContent,
  IonButton,
  IonList,
  IonItem,
  IonLabel,
  IonListHeader,
  useIonToast,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function ToastDemoPage() {
  const { t } = useTranslation();
  const [presentToast] = useIonToast();

  const showToast = (position: "top" | "bottom", color?: string) => {
    presentToast({
      message: t(`demos.toast.${color ?? position}`),
      duration: 1500,
      position,
      color,
    });
  };

  return (
    <IonPage>
      <PageHeader title={t("demos.toast.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.toast.title")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.toast.description")}</p>
            </IonLabel>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={() => showToast("top")}>
              {t("demos.toast.top")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" onClick={() => showToast("bottom")}>
              {t("demos.toast.bottom")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" color="success" onClick={() => showToast("bottom", "success")}>
              {t("demos.toast.success")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" color="warning" onClick={() => showToast("bottom", "warning")}>
              {t("demos.toast.warning")}
            </IonButton>
          </IonItem>
          <IonItem>
            <IonButton expand="block" color="danger" onClick={() => showToast("bottom", "danger")}>
              {t("demos.toast.danger")}
            </IonButton>
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
