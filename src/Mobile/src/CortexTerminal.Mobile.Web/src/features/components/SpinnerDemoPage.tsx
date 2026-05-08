import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonSpinner,
  IonGrid,
  IonRow,
  IonCol,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

const spinnerTypes = [
  { key: "lines", name: "lines" },
  { key: "linesSmall", name: "lines-small" },
  { key: "bubbles", name: "bubbles" },
  { key: "circles", name: "circles" },
  { key: "crescent", name: "crescent" },
  { key: "dots", name: "dots" },
] as const;

export default function SpinnerDemoPage() {
  const { t } = useTranslation();

  return (
    <IonPage>
      <PageHeader title={t("demos.spinner.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.spinner.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonGrid>
          <IonRow>
            {spinnerTypes.map((type) => (
              <IonCol key={type.key} size="6" sizeMd="4">
                <div style={{ textAlign: "center", padding: 16 }}>
                  <IonSpinner name={type.name} />
                  <IonLabel style={{ display: "block", marginTop: 8, fontSize: 13 }}>
                    {t(`demos.spinner.${type.key}`)}
                  </IonLabel>
                </div>
              </IonCol>
            ))}
          </IonRow>
        </IonGrid>
      </IonContent>
    </IonPage>
  );
}
