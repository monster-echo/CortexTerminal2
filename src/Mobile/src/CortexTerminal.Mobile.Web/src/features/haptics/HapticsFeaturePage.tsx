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

const sleep = (ms: number) => new Promise((resolve) => setTimeout(resolve, ms));

export default function HapticsFeaturePage() {
  const { t } = useTranslation();
  const [resultTitle, setResultTitle] = useState(t("haptics.initialTitle"));
  const [resultDetail, setResultDetail] =
    useState(t("haptics.initialDetail"));

  const runAction = async (title: string, action: () => Promise<string>) => {
    try {
      const detail = await action();
      setResultTitle(title);
      setResultDetail(detail);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setResultTitle(title);
      setResultDetail(`${t("haptics.errorPrefix")}${message}`);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("haptics.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <IonCard>
          <IonCardHeader>
            <IonCardTitle>{t("haptics.cardTitle")}</IonCardTitle>
            <IonCardSubtitle>{t("haptics.cardSubtitle")}</IonCardSubtitle>
          </IonCardHeader>
          <IonCardContent>
            {t("haptics.cardContent")}
          </IonCardContent>
        </IonCard>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("haptics.basicSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("haptics.click"), async () => {
                await nativeBridge.haptics("click");
                return t("haptics.clickResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("haptics.click")}</h2>
              <p>{t("haptics.clickDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("haptics.heavy"), async () => {
                await nativeBridge.haptics("heavy");
                return t("haptics.heavyResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("haptics.heavy")}</h2>
              <p>{t("haptics.heavyDesc")}</p>
            </IonLabel>
          </IonItem>

          <IonListHeader>
            <IonLabel>{t("haptics.comboSection")}</IonLabel>
          </IonListHeader>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("haptics.doubleClick"), async () => {
                await nativeBridge.haptics("click");
                await sleep(120);
                await nativeBridge.haptics("click");
                return t("haptics.doubleClickResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("haptics.doubleClick")}</h2>
              <p>{t("haptics.doubleClickDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("haptics.heavyClick"), async () => {
                await nativeBridge.haptics("heavy");
                await sleep(160);
                await nativeBridge.haptics("click");
                return t("haptics.heavyClickResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("haptics.heavyClick")}</h2>
              <p>{t("haptics.heavyClickDesc")}</p>
            </IonLabel>
          </IonItem>
          <IonItem
            button
            detail
            onClick={() =>
              void runAction(t("haptics.hapticToast"), async () => {
                await nativeBridge.haptics("heavy");
                await nativeBridge.showToastWithDuration(
                  t("haptics.hapticToastMsg"),
                  "short",
                );
                return t("haptics.hapticToastResult");
              })
            }
          >
            <IonLabel>
              <h2>{t("haptics.hapticToast")}</h2>
              <p>{t("haptics.hapticToastDesc")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <ActionResultCard title={resultTitle} detail={resultDetail} />
      </IonContent>
    </IonPage>
  );
}
