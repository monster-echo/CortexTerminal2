import {
  IonBadge,
  IonButton,
  IonButtons,
  IonCard,
  IonCardContent,
  IonCardHeader,
  IonCardSubtitle,
  IonCardTitle,
  IonContent,
  IonItem,
  IonLabel,
  IonList,
  IonListHeader,
  IonPage,
  IonText,
} from "@ionic/react";
import { useCallback, useEffect, useState } from "react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { nativeBridge, type PreferenceEntry } from "../../bridge/nativeBridge";
import ActionResultCard from "../../components/ActionResultCard";

export default function PreferencesFeaturePage() {
  const { t } = useTranslation();
  const [entries, setEntries] = useState<PreferenceEntry[]>([]);
  const [resultTitle, setResultTitle] = useState(t("preferences.initialTitle"));
  const [resultDetail, setResultDetail] = useState(
    t("preferences.initialDetail"),
  );

  const loadEntries = useCallback(async () => {
    try {
      const snapshot = await nativeBridge.getPreferenceEntries();
      setEntries(snapshot);
      setResultTitle(t("preferences.initialTitle"));
      setResultDetail(`${t("preferences.loadedDetail")}${snapshot.length}${t("preferences.loadedDetailEnd")}`);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(t("preferences.initialTitle"));
      setResultDetail(`${t("preferences.errorPrefix")}${message}`);
    }
  }, [t]);

  useEffect(() => {
    void loadEntries();
  }, [loadEntries]);

  const removeEntry = async (entry: PreferenceEntry) => {
    try {
      await nativeBridge.removeStringValue(entry.key);
      setResultTitle(`${t("preferences.cleared")}${entry.title}`);
      setResultDetail(`Key: ${entry.key}`);
      await loadEntries();
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(`${t("preferences.clearError")}${entry.title}`);
      setResultDetail(`${t("preferences.clearErrorPrefix")}${message}`);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("preferences.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("preferences.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>{t("preferences.cardSubtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            <IonText color="medium">
              {t("preferences.cardContent")}
            </IonText>
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("preferences.actionSection")}</IonLabel>
          </IonListHeader>
          <IonItem button detail onClick={() => void loadEntries()}>
            <IonLabel>
              <h2>{t("preferences.refresh")}</h2>
              <p>{t("preferences.refreshDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("preferences.listSection")}</IonLabel>
          </IonListHeader>
          {entries.map((entry) => (
            <IonItem key={entry.key}>
              <IonLabel>
                <h2>{entry.title}</h2>
                <p>{entry.description}</p>
                <p>
                  <strong>{entry.key}</strong>
                </p>
                <p>{t("preferences.category")}{entry.category}</p>
                <p>
                  {t("preferences.status")}
                  <IonBadge color={entry.exists ? "success" : "medium"}>
                    {entry.exists ? t("preferences.written") : t("preferences.notWritten")}
                  </IonBadge>
                </p>
                <p>
                  {t("preferences.value")}{entry.exists ? entry.value || t("preferences.emptyValue") : t("preferences.noValue")}
                </p>
              </IonLabel>
              <IonButtons slot="end">
                <IonButton
                  color="medium"
                  fill="outline"
                  onClick={() => void removeEntry(entry)}
                >
                  {t("preferences.clear")}
                </IonButton>
              </IonButtons>
            </IonItem>
          ))}
        </IonList>

        <ActionResultCard
          title={resultTitle}
          detail={resultDetail}
          note={t("preferences.note")}
        />
      </IonContent>
    </IonPage>
  );
}
