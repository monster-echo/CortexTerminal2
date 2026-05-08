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

export default function NotificationsFeaturePage() {
  const { t } = useTranslation();
  const [resultTitle, setResultTitle] = useState(t("notifications.initialTitle"));
  const [resultDetail, setResultDetail] = useState(
    t("notifications.initialDetail"),
  );

  const runAction = async (title: string, action: () => Promise<string>) => {
    try {
      const detail = await action();
      setResultTitle(title);
      setResultDetail(detail);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(title);
      setResultDetail(`${t("notifications.errorPrefix")}${message}`);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("notifications.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("notifications.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>{t("notifications.cardSubtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("notifications.cardContent")}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("notifications.displaySection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("notifications.inAppNotify"), async () => {
                await nativeBridge.showSnackbarWithOptions(
                  t("notifications.inAppNotifyMsg"),
                  null,
                  "short",
                );
                return t("notifications.inAppNotifyResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("notifications.inAppNotify")}</h2>
              <p>{t("notifications.inAppNotifyDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("notifications.highPriority"), async () => {
                await nativeBridge.haptics("heavy");
                await nativeBridge.showSnackbarWithOptions(
                  t("notifications.highPriorityMsg"),
                  t("notifications.highPriorityAction"),
                  "long",
                );
                return t("notifications.highPriorityResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("notifications.highPriority")}</h2>
              <p>{t("notifications.highPriorityDesc")}</p>
            </IonLabel>
          </IonItem>

          <IonListHeader>
            <IonLabel>{t("notifications.navSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("notifications.writeNav"), async () => {
                await nativeBridge.setPendingNavigation(
                  "/bridge",
                  JSON.stringify({ source: "notification-demo" }),
                );
                return t("notifications.writeNavResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("notifications.writeNav")}</h2>
              <p>{t("notifications.writeNavDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("notifications.writeMsgNav"), async () => {
                await nativeBridge.setPendingNavigation(
                  "/messages",
                  JSON.stringify({
                    source: "notification-demo",
                    type: "messages",
                  }),
                );
                return t("notifications.writeMsgNavResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("notifications.writeMsgNav")}</h2>
              <p>{t("notifications.writeMsgNavDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("notifications.readNav"), async () => {
                const pending = await nativeBridge.getPendingNavigation();
                return JSON.stringify(pending, null, 2);
              })
            }
          >
            <IonLabel>
              <h2>{t("notifications.readNav")}</h2>
              <p>{t("notifications.readNavDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("notifications.clearNav"), async () => {
                await nativeBridge.clearPendingNavigation();
                return t("notifications.clearNavResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("notifications.clearNav")}</h2>
              <p>{t("notifications.clearNavDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <ActionResultCard title={resultTitle} detail={resultDetail} />
      </IonContent>
    </IonPage>
  );
}
