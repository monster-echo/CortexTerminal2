import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonTextarea,
  IonListHeader,
  IonNote,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function TextareaDemoPage() {
  const { t } = useTranslation();
  const [autoGrowText, setAutoGrowText] = useState("");
  const [charCountText, setCharCountText] = useState("");
  const maxChars = 100;

  return (
    <IonPage>
      <PageHeader title={t("demos.textarea.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.textarea.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.textarea.autoGrow")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonTextarea
              placeholder={t("demos.textarea.placeholder")}
              autoGrow
              value={autoGrowText}
              onIonInput={(e) => setAutoGrowText(e.detail.value ?? "")}
              rows={3}
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.textarea.charCount", { current: charCountText.length, max: maxChars })}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonTextarea
              placeholder={t("demos.textarea.placeholder")}
              maxlength={maxChars}
              value={charCountText}
              onIonInput={(e) => setCharCountText(e.detail.value ?? "")}
              rows={3}
              counter
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.textarea.readonly")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonTextarea
              value={t("demos.textarea.readonlyContent")}
              readonly
              rows={3}
            />
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
