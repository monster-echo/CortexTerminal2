import {
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonContent,
  IonLabel,
  IonPage,
  IonSegment,
  IonSegmentButton,
  IonText,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import type { ColorMode } from "../../theme/colorMode";
import PageHeader from "../../components/PageHeader";

export interface ThemeFeaturePageProps {
  colorMode: ColorMode;
  onColorModeChange: (mode: ColorMode) => void;
}

export default function ThemeFeaturePage({
  colorMode,
  onColorModeChange,
}: ThemeFeaturePageProps) {
  const { t } = useTranslation();

  return (
    <IonPage>
      <PageHeader title={t("theme.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("theme.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>
              {t("theme.cardSubtitle")}
            </IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            <IonText color="medium">
              {t("theme.cardContent")}
            </IonText>
            <IonSegment
              value={colorMode}
              style={{ marginTop: 16 }}
              onIonChange={(event) => {
                const value = event.detail.value;
                if (value) {
                  onColorModeChange(value as ColorMode);
                }
              }}
            >
              <IonSegmentButton value="light">
                <IonLabel>{t("theme.light")}</IonLabel>
              </IonSegmentButton>
              <IonSegmentButton value="dark">
                <IonLabel>{t("theme.dark")}</IonLabel>
              </IonSegmentButton>
              <IonSegmentButton value="system">
                <IonLabel>{t("theme.system")}</IonLabel>
              </IonSegmentButton>
            </IonSegment>
          </IonCardContent>
        </IonCard>
      </IonContent>
    </IonPage>
  );
}
