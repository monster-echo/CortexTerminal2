import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonButton,
  IonBreadcrumb,
  IonBreadcrumbs,
  IonNote,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function NavDemoPage() {
  const { t } = useTranslation();
  const [stack, setStack] = useState<number[]>([1]);

  const handlePush = () => {
    setStack((prev) => [...prev, prev.length + 1]);
  };

  const handlePop = () => {
    if (stack.length > 1) {
      setStack((prev) => prev.slice(0, -1));
    }
  };

  const currentPage = stack[stack.length - 1];

  return (
    <IonPage>
      <PageHeader title={t("demos.nav.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.nav.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <div style={{ padding: "0 16px", marginBottom: 16 }}>
          <IonBreadcrumbs>
            {stack.map((page, index) => (
              <IonBreadcrumb key={index}>
                {t(`demos.nav.page${page <= 3 ? page : "1"}`)}
              </IonBreadcrumb>
            ))}
          </IonBreadcrumbs>
        </div>

        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <h2>{t("demos.nav.pushed", { count: currentPage })}</h2>
              <IonNote>
                {t("demos.nav.page" + (currentPage <= 3 ? currentPage : 1))}
              </IonNote>
            </IonLabel>
          </IonItem>
        </IonList>

        <div style={{ padding: "0 16px", display: "flex", gap: 12 }}>
          <IonButton expand="block" onClick={handlePush}>
            {t("demos.nav.push")}
          </IonButton>
          <IonButton
            expand="block"
            fill="outline"
            onClick={handlePop}
            disabled={stack.length <= 1}
          >
            {t("demos.nav.pop")}
          </IonButton>
        </div>
      </IonContent>
    </IonPage>
  );
}
