import {
  IonButton,
  IonCard,
  IonCardContent,
  IonContent,
  IonItem,
  IonLabel,
  IonList,
  IonPage,
  IonSegment,
  IonSegmentButton,
  IonText,
} from "@ionic/react";
import { useTranslation } from "react-i18next";
import { nativeBridge } from "../../bridge/nativeBridge";
import PageHeader from "../../components/PageHeader";
import { useAppStore } from "../../store/appStore";
import "../../pages/pageStyles.css";
export default function SettingsFeaturePage() {
  const { t, i18n } = useTranslation();
  const appInfo = useAppStore((state) => state.appInfo);
  const language = useAppStore((state) => state.language);
  const setLanguage = useAppStore((state) => state.setLanguage);

  const handleLanguageChange = (lang: "en" | "zh") => {
    setLanguage(lang);
    void i18n.changeLanguage(lang);
  };

  const shareApp = async () => {
    try {
      const fallbackName = t("settings.shareFallback");
      const appName = appInfo?.appName ?? fallbackName;
      await nativeBridge.shareText(
        appName,
        `${t("settings.shareMessage")}${appName}${t("settings.shareMessageEnd")}`,
      );
    } catch (error) {
      console.warn("Failed to share app", error);
    }
  };

  const contactSupport = async () => {
    try {
      await nativeBridge.composeSupportEmail(
        t("settings.emailSubject"),
        t("settings.emailBody"),
        appInfo?.supportEmail,
      );
    } catch (error) {
      console.warn("Failed to compose support email", error);
    }
  };

  return (
    <IonPage>
      <PageHeader title={t("settings.title")} defaultHref="/home" />
      <IonContent fullscreen>
        <div className="page-stack">
          <IonCard>
            <IonCardContent>
              <h2 className="page-title">{t("settings.supportSection")}</h2>
              <IonText color="medium">
                {t("settings.supportDesc")}
              </IonText>
              <IonButton
                expand="block"
                className="button-spacing"
                onClick={shareApp}
              >
                {t("settings.share")}
              </IonButton>
              <IonButton
                expand="block"
                fill="outline"
                className="button-spacing"
                onClick={contactSupport}
              >
                {t("settings.contact")}
              </IonButton>
            </IonCardContent>
          </IonCard>

          <IonCard>
            <IonCardContent>
              <h2 className="page-title">{t("settings.languageSection")}</h2>
              <IonText color="medium">
                {t("settings.languageDesc")}
              </IonText>
              <IonSegment
                value={language}
                style={{ marginTop: 16 }}
                onIonChange={(event) => {
                  const value = event.detail.value;
                  if (value === "en" || value === "zh") {
                    handleLanguageChange(value);
                  }
                }}
              >
                <IonSegmentButton value="zh">
                  <IonLabel>中文</IonLabel>
                </IonSegmentButton>
                <IonSegmentButton value="en">
                  <IonLabel>English</IonLabel>
                </IonSegmentButton>
              </IonSegment>
            </IonCardContent>
          </IonCard>

          <IonCard>
            <IonCardContent>
              <h2 className="page-title">{t("settings.linksSection")}</h2>
              <IonText color="medium">
                {t("settings.linksDesc")}
              </IonText>
              <IonButton
                expand="block"
                fill="outline"
                className="button-spacing"
                onClick={() =>
                  nativeBridge.openExternalLink(
                    appInfo?.privacyPolicyUrl ?? "https://example.com/privacy",
                  )
                }
              >
                {t("settings.privacy")}
              </IonButton>
              <IonButton
                expand="block"
                fill="outline"
                className="button-spacing"
                onClick={() =>
                  nativeBridge.openExternalLink(
                    appInfo?.termsOfServiceUrl ?? "https://example.com/terms",
                  )
                }
              >
                {t("settings.terms")}
              </IonButton>
            </IonCardContent>
          </IonCard>

          <IonCard>
            <IonCardContent>
              <h2 className="page-title">{t("settings.appInfoSection")}</h2>
              <IonList inset>
                {appInfo ? (
                  <>
                    <IonItem>
                      <IonLabel>
                        <strong>appName</strong>
                        <p>{appInfo.appName}</p>
                      </IonLabel>
                    </IonItem>
                    <IonItem>
                      <IonLabel>
                        <strong>version</strong>
                        <p>{appInfo.appVersion}</p>
                      </IonLabel>
                    </IonItem>
                    <IonItem>
                      <IonLabel>
                        <strong>packageIdentifier</strong>
                        <p>{appInfo.packageIdentifier}</p>
                      </IonLabel>
                    </IonItem>
                    <IonItem>
                      <IonLabel>
                        <strong>platform</strong>
                        <p>{appInfo.platform}</p>
                      </IonLabel>
                    </IonItem>
                    <IonItem>
                      <IonLabel>
                        <strong>supportEmail</strong>
                        <p>{appInfo.supportEmail}</p>
                      </IonLabel>
                    </IonItem>
                  </>
                ) : (
                  <IonItem>
                    <IonLabel>{t("settings.appInfoUnavailable")}</IonLabel>
                  </IonItem>
                )}
              </IonList>
            </IonCardContent>
          </IonCard>
        </div>
      </IonContent>
    </IonPage>
  );
}
