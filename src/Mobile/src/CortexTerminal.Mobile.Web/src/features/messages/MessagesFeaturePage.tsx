import {
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
} from "@ionic/react";
import { useState } from "react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";
import { nativeBridge } from "../../bridge/nativeBridge";
import ActionResultCard from "../../components/ActionResultCard";

export default function MessagesFeaturePage() {
  const { t } = useTranslation();
  const [resultTitle, setResultTitle] = useState(t("messages.initialTitle"));
  const [resultDetail, setResultDetail] =
    useState(t("messages.initialDetail"));

  const runAction = async (title: string, action: () => Promise<string>) => {
    try {
      const detail = await action();
      setResultTitle(title);
      setResultDetail(detail);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(title);
      setResultDetail(`${t("messages.errorPrefix")}${message}`);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("messages.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("messages.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>{t("messages.cardSubtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("messages.cardContent")}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("messages.toastSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.shortToast"), async () => {
                await nativeBridge.showToastWithDuration(
                  t("messages.shortToastMsg"),
                  "short",
                );
                return t("messages.shortToastResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.shortToast")}</h2>
              <p>{t("messages.shortToastDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.longToast"), async () => {
                await nativeBridge.showToastWithDuration(
                  t("messages.longToastMsg"),
                  "long",
                );
                return t("messages.longToastResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.longToast")}</h2>
              <p>{t("messages.longToastDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.dismissToast"), async () => {
                await nativeBridge.dismissToast();
                return t("messages.dismissToastResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.dismissToast")}</h2>
              <p>{t("messages.dismissToastDesc")}</p>
            </IonLabel>
          </IonItem>

          <IonListHeader>
            <IonLabel>{t("messages.snackbarSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.shortSnackbar"), async () => {
                await nativeBridge.showSnackbarWithOptions(
                  t("messages.shortSnackbarMsg"),
                  null,
                  "short",
                );
                return t("messages.shortSnackbarResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.shortSnackbar")}</h2>
              <p>{t("messages.shortSnackbarDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.longSnackbar"), async () => {
                await nativeBridge.showSnackbarWithOptions(
                  t("messages.longSnackbarMsg"),
                  null,
                  "long",
                );
                return t("messages.longSnackbarResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.longSnackbar")}</h2>
              <p>{t("messages.longSnackbarDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.cancelSnackbar"), async () => {
                await nativeBridge.showSnackbarWithOptions(
                  t("messages.cancelSnackbarMsg"),
                  t("messages.cancelSnackbarAction"),
                  "long",
                );
                return t("messages.cancelSnackbarResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.cancelSnackbar")}</h2>
              <p>{t("messages.cancelSnackbarDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.persistentSnackbar"), async () => {
                await nativeBridge.showSnackbarWithOptions(
                  t("messages.persistentSnackbarMsg"),
                  t("messages.persistentSnackbarAction"),
                  "indefinite",
                );
                return t("messages.persistentSnackbarResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.persistentSnackbar")}</h2>
              <p>{t("messages.persistentSnackbarDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.dismissSnackbar"), async () => {
                await nativeBridge.dismissSnackbar();
                return t("messages.dismissSnackbarResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.dismissSnackbar")}</h2>
              <p>{t("messages.dismissSnackbarDesc")}</p>
            </IonLabel>
          </IonItem>

          <IonListHeader>
            <IonLabel>{t("messages.comboSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("messages.comboLabel"), async () => {
                await nativeBridge.showToastWithDuration(
                  t("messages.comboToastMsg"),
                  "short",
                );
                await nativeBridge.haptics("click");
                return t("messages.comboResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("messages.comboLabel")}</h2>
              <p>{t("messages.comboDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <ActionResultCard title={resultTitle} detail={resultDetail} />
      </IonContent>
    </IonPage>
  );
}
