import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonGrid,
  IonRow,
  IonCol,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

const boxStyle = (color: string): React.CSSProperties => ({
  backgroundColor: color,
  padding: 12,
  textAlign: "center",
  borderRadius: 4,
  color: "#fff",
  fontWeight: "bold",
  marginBottom: 4,
});

export default function GridDemoPage() {
  const { t } = useTranslation();

  return (
    <IonPage>
      <PageHeader title={t("demos.grid.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.grid.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonGrid>
          <IonRow>
            <IonCol size="6">
              <div style={boxStyle("#3880ff")}>{t("demos.grid.col6")}</div>
            </IonCol>
            <IonCol size="6">
              <div style={boxStyle("#3dc2ff")}>{t("demos.grid.col6")}</div>
            </IonCol>
          </IonRow>

          <IonRow>
            <IonCol size="4">
              <div style={boxStyle("#5260ff")}>{t("demos.grid.col4")}</div>
            </IonCol>
            <IonCol size="4">
              <div style={boxStyle("#2dd36f")}>{t("demos.grid.col4")}</div>
            </IonCol>
            <IonCol size="4">
              <div style={boxStyle("#ffc409")}>{t("demos.grid.col4")}</div>
            </IonCol>
          </IonRow>

          <IonRow>
            <IonCol size="3">
              <div style={boxStyle("#eb445a")}>{t("demos.grid.col3")}</div>
            </IonCol>
            <IonCol size="3">
              <div style={boxStyle("#92949c")}>{t("demos.grid.col3")}</div>
            </IonCol>
            <IonCol size="3">
              <div style={boxStyle("#aa66be")}>{t("demos.grid.col3")}</div>
            </IonCol>
            <IonCol size="3">
              <div style={boxStyle("#0ecdba")}>{t("demos.grid.col3")}</div>
            </IonCol>
          </IonRow>

          <IonRow>
            <IonCol size="6" offset="3">
              <div style={boxStyle("#3880ff")}>{t("demos.grid.offset")}</div>
            </IonCol>
          </IonRow>

          <IonRow>
            <IonCol size="12" sizeMd="6" sizeLg="4">
              <div style={boxStyle("#5260ff")}>{t("demos.grid.responsive")}</div>
            </IonCol>
            <IonCol size="12" sizeMd="6" sizeLg="4">
              <div style={boxStyle("#2dd36f")}>{t("demos.grid.responsive")}</div>
            </IonCol>
            <IonCol size="12" sizeMd="6" sizeLg="4">
              <div style={boxStyle("#ffc409")}>{t("demos.grid.responsive")}</div>
            </IonCol>
          </IonRow>
        </IonGrid>
      </IonContent>
    </IonPage>
  );
}
