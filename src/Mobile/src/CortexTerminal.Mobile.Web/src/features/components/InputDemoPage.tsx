import { useState } from "react";
import {
  IonPage,
  IonContent,
  IonList,
  IonItem,
  IonLabel,
  IonInput,
  IonListHeader,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import PageHeader from "../../components/PageHeader";

export default function InputDemoPage() {
  const { t } = useTranslation();

  return (
    <IonPage>
      <PageHeader title={t("demos.input.title")} defaultHref="/components" />
      <IonContent fullscreen>
        <IonList inset>
          <IonItem>
            <IonLabel className="ion-text-wrap">
              <p>{t("demos.input.description")}</p>
            </IonLabel>
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.input.text")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonInput
              label={t("demos.input.text")}
              labelPlacement="stacked"
              type="text"
              placeholder={t("demos.input.textPlaceholder")}
              clearInput
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.input.email")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonInput
              label={t("demos.input.email")}
              labelPlacement="stacked"
              type="email"
              placeholder={t("demos.input.emailPlaceholder")}
              clearInput
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.input.password")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonInput
              label={t("demos.input.password")}
              labelPlacement="stacked"
              type="password"
              placeholder={t("demos.input.passwordPlaceholder")}
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.input.number")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonInput
              label={t("demos.input.number")}
              labelPlacement="stacked"
              type="number"
              placeholder={t("demos.input.numberPlaceholder")}
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.input.tel")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonInput
              label={t("demos.input.tel")}
              labelPlacement="stacked"
              type="tel"
              placeholder={t("demos.input.telPlaceholder")}
            />
          </IonItem>
        </IonList>

        <IonList inset>
          <IonListHeader>
            <IonLabel>{t("demos.input.clear")}</IonLabel>
          </IonListHeader>
          <IonItem>
            <IonInput
              label={t("demos.input.clear")}
              labelPlacement="stacked"
              placeholder={t("demos.input.clearPlaceholder")}
              clearInput
            />
          </IonItem>
        </IonList>
      </IonContent>
    </IonPage>
  );
}
